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
end
