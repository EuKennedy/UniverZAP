require 'rails_helper'

RSpec.describe Ai::AutopilotReplyJob, type: :job do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account, inbox: conversation.inbox) }
  # Bypass the real Claude/belezaki round-trip — we only exercise the job's
  # locking / dedup / guard logic here.
  let(:service) { instance_double(Ai::AutopilotReplyService, perform: { content: 'Olá!' }) }

  after do
    Current.reset
    Redis::Alfred.delete(format(Redis::RedisKeys::AUTOPILOT_REPLY_RATE, conversation_id: conversation.id))
  end

  def outgoing_count
    conversation.reload.messages.where(message_type: :outgoing).count
  end

  it 'posts one reply and stamps the trigger message id on the conversation' do
    allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)

    expect { described_class.perform_now(message.id, assistant.id) }.to change { outgoing_count }.by(1)
    expect(conversation.reload.additional_attributes['autopilot_last_replied_message_id']).to eq(message.id)
  end

  it 'does not post a second reply when the same job is retried (dedup by message_id)' do
    allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)
    described_class.perform_now(message.id, assistant.id)

    expect { described_class.perform_now(message.id, assistant.id) }.not_to(change { outgoing_count })
  end

  it 'aborts without replying when the assistant belongs to another account' do
    other_assistant = create(:ai_assistant, account: create(:account))

    expect(Ai::AutopilotReplyService).not_to receive(:new)
    expect { described_class.perform_now(message.id, other_assistant.id) }.not_to(change { outgoing_count })
  end

  it 'resets Current on the way out so it never leaks to the next job on the thread' do
    allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)
    Current.account = create(:account) # stale value a previous job could have left on the thread

    described_class.perform_now(message.id, assistant.id)

    expect(Current.account).to be_nil
  end

  describe 'rate limiting (Redis sliding window)' do
    it 'stops replying once the per-minute limit is reached' do
      allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)
      assistant.update!(guardrails: { 'max_messages_per_minute' => 1 })
      described_class.perform_now(message.id, assistant.id) # first reply records one hit
      next_trigger = create(:message, conversation: conversation, account: account, inbox: conversation.inbox)

      expect { described_class.perform_now(next_trigger.id, assistant.id) }.not_to(change { outgoing_count })
    end

    it 'falls back to the DB count and still replies when Redis is unavailable' do
      allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)
      allow(Redis::SlidingWindowRateLimiter).to receive(:new).and_raise(StandardError, 'redis down')

      expect { described_class.perform_now(message.id, assistant.id) }.to change { outgoing_count }.by(1)
    end
  end

  describe 'pipeline hardening (Sprint 8)' do
    it 'runs on its own lane so a customer turn never waits behind bulk jobs' do
      expect(described_class.new.queue_name).to eq('ai_replies')
    end

    it 'retries the turn instead of swallowing a transient upstream failure' do
      allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)
      allow(service).to receive(:perform).and_raise(Ai::ClaudeService::TransientError, 'Claude API 503')

      expect { described_class.perform_now(message.id, assistant.id) }.to have_enqueued_job(described_class)
    end

    it 'does not retry a permanent failure (no retry storm on a bad key)' do
      allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)
      allow(service).to receive(:perform).and_raise(Ai::ClaudeService::Error, 'Anthropic API key not configured')

      expect { described_class.perform_now(message.id, assistant.id) }.not_to have_enqueued_job(described_class)
    end

    it 'drops a stale turn when a newer message was already answered' do
      conversation.update!(additional_attributes: { 'autopilot_last_replied_message_id' => message.id + 10 })

      expect(Ai::AutopilotReplyService).not_to receive(:new)
      expect { described_class.perform_now(message.id, assistant.id) }.not_to(change { outgoing_count })
    end
  end

  # "Nenhuma resposta enviada sem log gravado": the row is written before the
  # send, so every one of them has to reach a terminal state. A row left pending
  # means a generated reply nobody can account for.
  describe 'delivery accounting' do
    def pending_invocation(trigger: message.id)
      create(:ai_invocation, account: account, ai_assistant: assistant, phase: 'autopilot',
                             conversation_id: conversation.id, delivery_status: 'pending',
                             trigger_message_id: trigger)
    end

    it 'marks the log delivered and links it to the message the customer received' do
      allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)
      invocation = pending_invocation

      described_class.perform_now(message.id, assistant.id)

      invocation.reload
      expect(invocation.delivery_status).to eq('sent')
      expect(invocation.message_id).to eq(conversation.messages.where(message_type: :outgoing).last.id)
    end

    it 'closes the log as a handoff when the guardrails suppressed the reply' do
      allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)
      allow(service).to receive(:perform).and_raise(Ai::AutopilotReplyService::UngroundedClaim)
      invocation = pending_invocation

      described_class.perform_now(message.id, assistant.id)

      invocation.reload
      expect(invocation.delivery_status).to eq('failed')
      expect(invocation.handoff).to be(true)
    end

    it 'closes the log as failed, not handed off, when the call itself broke' do
      allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)
      allow(service).to receive(:perform).and_raise(Ai::ClaudeService::Error, 'bad key')
      invocation = pending_invocation

      described_class.perform_now(message.id, assistant.id)

      invocation.reload
      expect(invocation.delivery_status).to eq('failed')
      expect(invocation.handoff).to be(false)
    end

    # A retry is coming, so the row must stay open: closing it here would make
    # the successful attempt look like a second, unexplained reply.
    it 'leaves the log open on a transient failure that will be retried' do
      allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)
      allow(service).to receive(:perform).and_raise(Ai::ClaudeService::TransientError, '503')
      invocation = pending_invocation

      described_class.perform_now(message.id, assistant.id)

      expect(invocation.reload.delivery_status).to eq('pending')
    end

    # Scoping used to be "same conversation, last 5 minutes", which swept up the
    # neighbouring turn: a reply the guardrails had just suppressed would be
    # relabelled as delivered by the NEXT turn, erasing the audit trail.
    it 'never relabels an already closed row from a neighbouring turn' do
      allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)
      earlier = create(:message, conversation: conversation, account: account, inbox: conversation.inbox)
      closed = pending_invocation(trigger: earlier.id)
      closed.update!(delivery_status: 'failed', handoff: true)

      described_class.perform_now(message.id, assistant.id)

      closed.reload
      expect(closed.delivery_status).to eq('failed')
      expect(closed.message_id).to be_nil
    end

    it 'closes the turn when the retries run out instead of leaving it open forever' do
      invocation = pending_invocation

      described_class.close_out_turn!(conversation, assistant.id, message.id, handoff: false)

      expect(invocation.reload.delivery_status).to eq('failed')
    end
  end
end
