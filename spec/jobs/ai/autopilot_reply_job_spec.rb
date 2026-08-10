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

  # A tenant that asked for it gets one bubble per paragraph, the way a person
  # types on WhatsApp. Off by default, because an agent that suddenly fires four
  # notifications instead of one is a change the tenant has to choose.
  describe 'split_messages behaviour flag' do
    let(:split_content) do
      "Oi, tudo bem?\n\nO Volume Control Blond sai por R$ 219.\n\nQuer que eu mande o link?"
    end
    let(:long_reply) { instance_double(Ai::AutopilotReplyService, perform: { content: split_content }) }

    before { allow(Ai::AutopilotReplyService).to receive(:new).and_return(long_reply) }

    it 'sends one message per paragraph when the flag is on' do
      assistant.update!(behavior_flags: { 'split_messages' => true })

      expect { described_class.perform_now(message.id, assistant.id) }.to change { outgoing_count }.by(3)
    end

    it 'sends a single message when the flag is off' do
      expect { described_class.perform_now(message.id, assistant.id) }.to change { outgoing_count }.by(1)
    end

    # The reply still has to read whole in supervision, so the history row must
    # not end up holding only the last bubble.
    it 'keeps the paragraphs in order' do
      assistant.update!(behavior_flags: { 'split_messages' => true })
      described_class.perform_now(message.id, assistant.id)

      sent = conversation.reload.messages.where(message_type: :outgoing).order(:id).pluck(:content)

      expect(sent.first).to include('tudo bem')
      expect(sent.last).to include('link')
    end
  end

  # The WhatsApp reply arrow: the answer arrives quoting the question it
  # answers. Worth pinning end to end rather than at the unit, because the value
  # has to survive Messages::MessageBuilder — which reads `in_reply_to` out of
  # content_attributes only for ActionController::Parameters and then assigns
  # the resulting nil back over the key, silently dropping the quote on the
  # plain-Hash path this job uses.
  describe 'reply_marking behaviour flag' do
    # What an inbound WhatsApp message carries: the provider's own id.
    let(:message) do
      create(:message, conversation: conversation, account: account, inbox: conversation.inbox,
                       source_id: 'wamid.HBgNNTUxMTk5OTk5OTk5ORUCABIYFjNFQjA=')
    end

    before do
      allow(Ai::AutopilotReplyService).to receive(:new).and_return(service)
      assistant.update!(behavior_flags: { 'reply_marking' => true })
    end

    # `private: false` on purpose — a private note is an outgoing message too,
    # and one of the cases below plants one deliberately.
    def agent_replies
      conversation.reload.messages.where(message_type: :outgoing, private: false).order(:id)
    end

    def first_outgoing
      agent_replies.first
    end

    def quoted_ids
      agent_replies.map { |m| m.content_attributes['in_reply_to_external_id'] }
    end

    # An earlier message nobody answered, so the trigger stops being the only
    # thing waiting. Created before `message` is referenced, so its id is lower.
    def earlier!(content)
      create(:message, conversation: conversation, account: account, inbox: conversation.inbox,
                       content: content, source_id: 'wamid.FIRST')
    end

    it 'quotes a direct question' do
      message.update!(content: 'Quanto custa a progressiva blond?')

      described_class.perform_now(message.id, assistant.id)

      expect(first_outgoing.content_attributes['in_reply_to_external_id']).to eq(message.source_id)
    end

    # Nobody types the question mark on a phone.
    it 'quotes a question that never got its question mark' do
      message.update!(content: 'tem essa progressiva em 1L')

      described_class.perform_now(message.id, assistant.id)

      expect(first_outgoing.content_attributes['in_reply_to_external_id']).to eq(message.source_id)
    end

    # The tic the operator objected to: "quanto custa?" → "R$ 299" → "ok, vou
    # levar", and the agent quoting that last one too. There is nothing there to
    # disambiguate.
    it 'leaves a statement alone' do
      message.update!(content: 'ok, vou levar entao')

      described_class.perform_now(message.id, assistant.id)

      expect(first_outgoing.content_attributes['in_reply_to_external_id']).to be_nil
    end

    # The burst arrives as one thought and is answered once, so the arrow has to
    # point at the question in it, not at whichever fragment happened last.
    it 'reaches past the small talk to the question behind it' do
      earlier!('oi bom dia')
      message.update!(content: 'quanto custa a progressiva?')

      described_class.perform_now(message.id, assistant.id)

      expect(first_outgoing.content_attributes['in_reply_to_external_id']).to eq(message.source_id)
    end

    # A human's internal note is invisible to the customer, so it never counts
    # as having replied to them — the question is still unanswered.
    it 'still finds the question when the only reply since was a private note' do
      earlier!('vocês entregam em SP?')
      create(:message, conversation: conversation, account: account, inbox: conversation.inbox,
                       message_type: :outgoing, private: true, content: 'cliente VIP')

      described_class.perform_now(message.id, assistant.id)

      expect(first_outgoing.content_attributes['in_reply_to_external_id']).to eq('wamid.FIRST')
    end

    # Message#ensure_in_reply_to resolves the pair from the external id, scoped
    # to this conversation — which is what keeps a quote from ever pointing at
    # another tenant's message.
    it 'resolves the quote back to a real message row in this conversation' do
      first = earlier!('vocês entregam em SP?')

      described_class.perform_now(message.id, assistant.id)

      expect(first_outgoing.content_attributes['in_reply_to']).to eq(first.id)
    end

    it 'sends a plain reply when the flag is off' do
      assistant.update!(behavior_flags: {})
      message.update!(content: 'Quanto custa?')

      described_class.perform_now(message.id, assistant.id)

      expect(first_outgoing.content_attributes['in_reply_to_external_id']).to be_nil
    end

    # Playground and API inboxes have no provider id to quote.
    it 'sends a plain reply when the message carries no provider id' do
      message.update!(content: 'Quanto custa?', source_id: nil)

      described_class.perform_now(message.id, assistant.id)

      expect(first_outgoing.content_attributes['in_reply_to_external_id']).to be_nil
    end

    # WhatsApp draws one quoted header per message, so repeating it on every
    # bubble of a split reply is noise rather than context.
    it 'quotes only the first bubble when the reply is split' do
      assistant.update!(behavior_flags: { 'reply_marking' => true, 'split_messages' => true })
      allow(Ai::AutopilotReplyService).to receive(:new).and_return(
        instance_double(Ai::AutopilotReplyService, perform: { content: "Oi, tudo bem?\n\nO produto sai por R$ 219,00." })
      )
      message.update!(content: 'Quanto custa?')

      described_class.perform_now(message.id, assistant.id)

      expect(quoted_ids).to eq([message.source_id, nil])
    end
  end

  # The customer who thinks out loud: "oi" / "vc tem a progressiva?" / "aquela
  # de 1L" is one question typed in three bursts, and used to buy three Claude
  # calls and send three replies.
  describe 'a burst of messages from the same customer' do
    before { allow(Ai::AutopilotReplyService).to receive(:new).and_return(service) }

    def next_message!
      create(:message, conversation: conversation, account: account, inbox: conversation.inbox)
    end

    it 'stands down when the customer has already typed again' do
      trigger = message
      next_message!

      expect { described_class.perform_now(trigger.id, assistant.id) }.not_to(change { outgoing_count })
    end

    it 'answers a burst exactly once' do
      first = message
      second = next_message!
      third = next_message!

      [first, second, third].each { |m| described_class.perform_now(m.id, assistant.id) }

      expect(outgoing_count).to eq(1)
    end

    # Standing down must not spend the turn: the whole point is that the burst
    # costs one call, not one per fragment.
    it 'never reaches Claude for the fragments it stands down on' do
      trigger = message
      next_message!

      described_class.perform_now(trigger.id, assistant.id)

      expect(Ai::AutopilotReplyService).not_to have_received(:new)
    end
  end

  describe '#split_on_paragraphs' do
    let(:job) { described_class.new }

    it 'glues a fragment too short to be its own message onto the one before it' do
      parts = job.send(:split_on_paragraphs, "Claro!\n\nO produto custa R$ 219,00 e sai hoje.")

      expect(parts.length).to eq(1)
      expect(parts.first).to start_with('Claro!')
    end

    it 'never bursts past the cap' do
      parts = job.send(:split_on_paragraphs, (1..9).map { |i| "Paragrafo numero #{i} com texto." }.join("\n\n"))

      expect(parts.length).to eq(described_class::MAX_PARTS)
      expect(parts.last).to include('numero 9')
    end
  end
end
