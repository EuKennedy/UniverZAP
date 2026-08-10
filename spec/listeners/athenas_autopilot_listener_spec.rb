require 'rails_helper'

# The listener decides whether a bot speaks to a real customer, so every way of
# switching autopilot on — and the one way of switching it off — is pinned here.
RSpec.describe AthenasAutopilotListener do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account, autopilot_enabled: false) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
  end

  def dispatch
    described_class.new.message_created(
      Events::Base.new('message.created', Time.zone.now, message: message)
    )
  end

  def enqueued?
    dispatch
    enqueued_jobs.any? { |job| job['job_class'] == 'Ai::AutopilotReplyJob' || job[:job] == Ai::AutopilotReplyJob }
  end

  before { inbox.update!(ai_assistant: assistant) }

  # What the checkbox on the agent screen has always claimed to do.
  context 'when the agent has autopilot switched on' do
    before { assistant.update!(autopilot_enabled: true) }

    it 'answers without the operator arming the conversation or the inbox' do
      expect(enqueued?).to be(true)
    end

    # The operator's escape hatch. It has to beat the agent's own switch, or
    # there is no way to take over a conversation where the customer asked for
    # a human short of switching the agent off for everybody.
    it 'stays silent on a conversation the operator silenced' do
      conversation.update!(additional_attributes: { 'autopilot_enabled' => false })

      expect(enqueued?).to be(false)
    end
  end

  context 'when the agent has autopilot switched off' do
    it 'stays silent by default' do
      expect(enqueued?).to be(false)
    end

    it 'answers a conversation the operator armed by hand' do
      conversation.update!(
        additional_attributes: { 'autopilot_enabled' => true, 'autopilot_assistant_id' => assistant.id }
      )

      expect(enqueued?).to be(true)
    end

    # Accounts that drive autopilot at the inbox instead of on the agent kept
    # working through this change.
    it 'answers when the inbox itself is in autopilot mode' do
      inbox.update!(ai_mode: 'autopilot')

      expect(enqueued?).to be(true)
    end
  end

  it 'never answers when the agent is inactive, however autopilot was switched on' do
    assistant.update!(autopilot_enabled: true, active: false)

    expect(enqueued?).to be(false)
  end
end
