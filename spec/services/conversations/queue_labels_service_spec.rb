require 'rails_helper'

RSpec.describe Conversations::QueueLabelsService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, status: :open) }

  before do
    %w[novo-contato triagem em-atendimento vip].each { |title| create(:label, account: account, title: title) }
    create(:label, account: account, title: 'atendimento-encerrado', closes_conversation: true)
    conversation.update_labels(%w[novo-contato vip])
  end

  it 'moves the stage to em-atendimento when an agent replies' do
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox,
                     message_type: :outgoing, sender: agent)

    expect(conversation.reload.label_list).to contain_exactly('em-atendimento', 'vip')
  end

  it 'keeps the stage on an automatic message' do
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox,
                     message_type: :outgoing, sender: create(:agent_bot, account: account))

    expect(conversation.reload.label_list).to contain_exactly('novo-contato', 'vip')
  end

  it 'drops the stage tags when the conversation is resolved' do
    conversation.reload.resolved!

    expect(conversation.reload.label_list).to contain_exactly('vip')
  end

  it 'brings em-atendimento back and clears the closing tag when it reopens' do
    conversation.reload.add_labels(['atendimento-encerrado'])
    conversation.reload.open!

    expect(conversation.reload.label_list).to contain_exactly('em-atendimento', 'vip')
  end

  it 'leaves accounts without the stage flow alone' do
    account.labels.find_by(title: 'em-atendimento').destroy!
    conversation.reload.resolved!

    expect(conversation.reload.label_list).to include('novo-contato')
  end
end
