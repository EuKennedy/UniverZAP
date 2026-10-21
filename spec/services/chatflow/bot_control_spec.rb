require 'rails_helper'

RSpec.describe Chatflow::BotControl do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:chatflow) { Chatflow.create!(account: account, name: 'SAC', inbox: inbox, status: :active, trigger_type: :any_message) }
  let!(:menu) { flow_node(chatflow, :menu, 'text' => 'Escolha', 'options' => [{ 'label' => 'Preço', 'value' => 'preco' }]) }
  let(:listener) { ChatflowListener.instance }

  before do
    chatflow.update!(start_node: menu)
    flow_edge(menu, flow_node(chatflow, :send_message, 'text' => 'Custa R$ 50'), 'preco')
  end

  def agent_replies(text = 'Oi, aqui é a Ana')
    message = create(:message, conversation: conversation, account: account, message_type: 'outgoing', sender: agent, content: text)
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  it 'pausa quando um atendente responde no meio do fluxo e não deixa gatilho novo começar' do
    customer_says(conversation, 'oi')
    agent_replies

    execution = ChatflowExecution.last
    expect(execution).to be_status_paused
    expect(described_class.paused?(conversation.reload)).to be(true)
    expect(described_class.new(conversation).state).to include(paused: true, paused_by: agent.name)

    customer_says(conversation, '1')
    expect(bot_said(conversation)).to eq(["Escolha\n\n1- Preço", 'Oi, aqui é a Ana'])
  end

  it 'resposta pelo celular (nota 📱) também pausa' do
    customer_says(conversation, 'oi')
    note = create(:message, conversation: conversation, account: account, message_type: 'outgoing', private: true,
                            content: "*📱 Enviado do WhatsApp*\nJá te respondo")
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: note))

    expect(ChatflowExecution.last).to be_status_paused
  end

  it 'não pausa quando o fluxo desligou a opção' do
    chatflow.update!(trigger_config: { 'pause_on_agent_reply' => false })
    customer_says(conversation, 'oi')
    agent_replies

    expect(ChatflowExecution.last).to be_status_waiting_input
  end

  it 'retomar devolve a execução para onde estava' do
    customer_says(conversation, 'oi')
    agent_replies
    described_class.new(conversation.reload).resume!

    expect(ChatflowExecution.last).to be_status_waiting_input
    customer_says(conversation.reload, '1')
    expect(bot_said(conversation).last).to eq('Custa R$ 50')
  end

  it 'a pausa automática vence sozinha' do
    customer_says(conversation, 'oi')
    agent_replies
    travel 25.hours do
      expect(described_class.paused?(conversation.reload)).to be(false)
    end
  end

  it 'resolver a conversa limpa a pausa e encerra a execução pausada' do
    customer_says(conversation, 'oi')
    described_class.new(conversation).pause!(by: agent)
    listener.conversation_resolved(Events::Base.new('conversation.resolved', Time.zone.now, conversation: conversation.reload))

    expect(described_class.paused?(conversation.reload)).to be(false)
    expect(ChatflowExecution.last).to be_status_aborted
  end
end
