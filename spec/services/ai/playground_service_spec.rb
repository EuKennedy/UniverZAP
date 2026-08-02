require 'rails_helper'

RSpec.describe Ai::PlaygroundService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:service) { described_class.new(account: account, assistant: assistant, user: user) }
  let(:reply) { instance_double(Ai::AutopilotReplyService, perform: { content: 'Claro, posso ajudar!' }) }

  before do
    allow(Ai::AutopilotReplyService).to receive(:new).and_return(reply)
    allow(reply).to receive(:playground_diagnostics).and_return(
      { knowledge_titles: ['Preços'], knowledge_chars: 120, regenerated_for_grounding: false, regenerated_for_loop: false }
    )
  end

  it 'answers through the real autopilot service, not a reimplementation' do
    result = service.send_message('quanto custa?')

    expect(Ai::AutopilotReplyService).to have_received(:new)
    expect(result[:content]).to eq('Claro, posso ajudar!')
  end

  it 'keeps the transcript so the operator can test a multi-turn scenario' do
    service.send_message('oi')
    service.send_message('quanto custa?')

    expect(service.transcript.map { |m| m[:role] }).to eq(%w[user assistant user assistant])
  end

  it 'reports which knowledge the agent actually used' do
    result = service.send_message('quanto custa?')

    expect(result[:diagnostics][:knowledge_titles]).to eq(['Preços'])
  end

  it 'reports a suppressed reply as a result, not as a crash' do
    allow(reply).to receive(:perform).and_raise(Ai::AutopilotReplyService::UngroundedClaim)

    result = service.send_message('me da um desconto')

    expect(result[:status]).to eq('ungrounded_claim')
    expect(result[:content]).to be_nil
  end

  describe 'isolation from real customers' do
    it 'hides the sandbox conversation from every conversation list' do
      service.send_message('oi')

      expect(account.conversations.not_sandbox).to be_empty
      expect(account.conversations.count).to eq(1)
    end

    it 'gives each operator their own transcript for the same assistant' do
      other_user = create(:user, account: account, role: :administrator)
      service.send_message('oi do primeiro')
      described_class.new(account: account, assistant: assistant, user: other_user).send_message('oi do segundo')

      expect(account.conversations.count).to eq(2)
    end

    # Production posts bot replies with no sender. Diverging here would make the
    # bot's own invented price count as a human-authored source on the next
    # turn, silently disabling the grounding guard: the playground would be MORE
    # permissive than production, the one direction it must never fail in.
    it 'writes the reply with no sender, exactly like production' do
      service.send_message('oi')

      outgoing = account.conversations.first.messages.find_by(message_type: :outgoing)
      expect(outgoing.sender_id).to be_nil
    end

    it 'never lets a sandbox turn reach a customer webhook or an automation rule' do
      service.send_message('oi')
      conversation = account.conversations.first
      event = Struct.new(:data).new({ conversation: conversation })

      expect(conversation).to be_sandbox
      expect(WebhookListener.instance.sandbox_event?(event)).to be(true)
    end

    it 'keeps the sandbox out of the live conversation metrics' do
      service.send_message('oi')

      expect(account.conversations.open.not_sandbox.count).to eq(0)
    end

    it 'parks the sandbox on an inbox with nowhere to deliver' do
      service.send_message('oi')

      inbox = account.inboxes.find_by(name: described_class::SANDBOX_INBOX_NAME)
      expect(inbox.channel).to be_a(Channel::Api)
      expect(inbox.channel.webhook_url).to be_blank
    end
  end

  it 'wipes the transcript on reset' do
    service.send_message('oi')

    service.reset!

    expect(service.transcript).to be_empty
  end
end
