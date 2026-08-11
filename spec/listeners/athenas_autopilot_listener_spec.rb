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

  # The turn is scheduled through .set(wait:) so the rest of a customer's burst
  # can land before it starts, which puts perform_later on the configured job
  # rather than on the job class.
  let(:scheduled) { instance_double(ActiveJob::ConfiguredJob, perform_later: nil) }

  before do
    inbox.update!(ai_assistant: assistant)
    allow(Ai::AutopilotReplyJob).to receive(:set).and_return(scheduled)
  end

  def dispatch
    described_class.instance.message_created(
      Events::Base.new('message.created', Time.zone.now, message: message)
    )
  end

  # What the checkbox on the agent screen has always claimed to do.
  context 'when the agent has autopilot switched on' do
    before { assistant.update!(autopilot_enabled: true) }

    it 'answers without the operator arming the conversation or the inbox' do
      dispatch

      expect(scheduled).to have_received(:perform_later).with(message.id, assistant.id)
    end

    # The operator's escape hatch. It has to beat the agent's own switch, or
    # there is no way to take over a conversation where the customer asked for
    # a human short of switching the agent off for everybody.
    it 'stays silent on a conversation the operator silenced' do
      conversation.update!(additional_attributes: { 'autopilot_enabled' => false })

      dispatch

      expect(scheduled).not_to have_received(:perform_later)
    end
  end

  context 'when the agent has autopilot switched off' do
    it 'stays silent by default' do
      dispatch

      expect(scheduled).not_to have_received(:perform_later)
    end

    it 'answers a conversation the operator armed by hand' do
      conversation.update!(
        additional_attributes: { 'autopilot_enabled' => true, 'autopilot_assistant_id' => assistant.id }
      )

      dispatch

      expect(scheduled).to have_received(:perform_later).with(message.id, assistant.id)
    end

    # Accounts that drive autopilot at the inbox instead of on the agent kept
    # working through this change.
    it 'answers when the inbox itself is in autopilot mode' do
      inbox.update!(ai_mode: 'autopilot')

      dispatch

      expect(scheduled).to have_received(:perform_later).with(message.id, assistant.id)
    end
  end

  # A group is several people talking to each other, not a customer talking to
  # the shop, and the agent cannot tell which messages are addressed to it.
  # Answering them all is the fastest way to get the number reported, so this
  # guard is ON until somebody deliberately turns it off.
  describe 'group chats' do
    let(:contact) { create(:contact, account: account, identifier: '551199999999-1234@g.us') }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    before { assistant.update!(autopilot_enabled: true) }

    it 'stays out of a group without anyone configuring anything' do
      dispatch

      expect(scheduled).not_to have_received(:perform_later)
    end

    # Every agent that predates the flag reads nil, and nil has to mean ON.
    it 'stays out of a group for an agent that has never seen this setting' do
      assistant.update!(behavior_flags: { 'split_messages' => true })

      dispatch

      expect(scheduled).not_to have_received(:perform_later)
    end

    it 'answers a group only once the operator switches the guard off' do
      assistant.update!(behavior_flags: { 'skip_groups' => false })

      dispatch

      expect(scheduled).to have_received(:perform_later).with(message.id, assistant.id)
    end
  end

  it 'keeps answering an ordinary one-to-one conversation' do
    assistant.update!(autopilot_enabled: true)

    dispatch

    expect(scheduled).to have_received(:perform_later).with(message.id, assistant.id)
  end

  # The debounce window is what lets a customer finish a thought typed in three
  # bursts before the agent starts answering the first line of it.
  it 'schedules the turn behind the debounce window' do
    assistant.update!(autopilot_enabled: true)

    dispatch

    expect(Ai::AutopilotReplyJob).to have_received(:set).with(wait: Ai::AutopilotReplyJob::DEBOUNCE_WINDOW)
  end

  it 'never answers when the agent is inactive, however autopilot was switched on' do
    assistant.update!(autopilot_enabled: true, active: false)

    dispatch

    expect(scheduled).not_to have_received(:perform_later)
  end
end
