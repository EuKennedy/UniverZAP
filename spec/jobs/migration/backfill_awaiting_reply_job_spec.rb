require 'rails_helper'

RSpec.describe Migration::BackfillAwaitingReplyJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def conversation_with(*message_types)
    conversation = create(:conversation, account: account, inbox: inbox)
    message_types.each { |type| create(:message, conversation: conversation, message_type: type) }
    conversation.update_columns(awaiting_reply: false) # rubocop:disable Rails/SkipsModelValidations
    conversation
  end

  it 'marks the conversations whose contact spoke last, ignoring notes, activities and templates' do
    contact_last = conversation_with(:outgoing, :incoming, :activity, :template)
    agent_last = conversation_with(:incoming, :outgoing)
    note_last = conversation_with(:incoming).tap do |conversation|
      create(:message, conversation: conversation, message_type: :outgoing, private: true)
      conversation.update_columns(awaiting_reply: false) # rubocop:disable Rails/SkipsModelValidations
    end

    described_class.perform_now

    expect(contact_last.reload.awaiting_reply).to be(true)
    expect(agent_last.reload.awaiting_reply).to be(false)
    expect(note_last.reload.awaiting_reply).to be(true)
  end
end
