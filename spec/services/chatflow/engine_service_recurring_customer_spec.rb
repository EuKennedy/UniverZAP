require 'rails_helper'

RSpec.describe Chatflow::EngineService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:chatflow) { Chatflow.create!(account: account, name: 'Bem-vinda de volta', inbox: inbox, status: :active, trigger_type: :recurring_customer) }
  let!(:greeting) do
    ChatflowNode.create!(chatflow: chatflow, account: account, kind: :send_message, config: { 'text' => 'Que bom te ver de novo!' })
  end

  def inbound(content)
    create(:message, conversation: conversation, account: account, message_type: 'incoming', content: content)
  end

  before { chatflow.update!(start_node: greeting) }

  it 'starts the flow on the first message of a customer whose previous conversation ended' do
    create(:conversation, account: account, inbox: inbox, contact: contact, status: :resolved)

    described_class.new(inbound('oi, quero marcar de novo')).perform

    expect(conversation.messages.outgoing.pluck(:content)).to eq(['Que bom te ver de novo!'])
  end

  it 'does not start again on later messages of the same conversation' do
    create(:conversation, account: account, inbox: inbox, contact: contact, status: :resolved)
    described_class.new(inbound('oi')).perform

    described_class.new(inbound('tem horário sábado?')).perform

    expect(ChatflowExecution.where(chatflow: chatflow).count).to eq(1)
  end

  it 'stays quiet for a first-time customer' do
    described_class.new(inbound('oi, quero marcar')).perform

    expect(ChatflowExecution.where(chatflow: chatflow).count).to eq(0)
  end
end
