require 'rails_helper'

RSpec.describe Chatflow::EngineService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:chatflow) { Chatflow.create!(account: account, name: 'Cadastro', inbox: inbox, status: :active, trigger_type: :any_message) }

  let!(:question) do
    flow_node(chatflow, :question, 'text' => 'Qual seu e-mail?', 'field_type' => 'email',
                                   'save_to' => { 'scope' => 'contact', 'key' => 'email' },
                                   'error_text' => 'Esse e-mail não parece certo.', 'max_attempts' => 2)
  end
  let!(:thanks) { flow_node(chatflow, :send_message, 'text' => 'Obrigada!') }
  let!(:human) { flow_node(chatflow, :send_message, 'text' => 'Vou chamar a equipe.') }

  before do
    chatflow.update!(start_node: question)
    flow_edge(question, thanks)
    flow_edge(question, human, ChatflowNode::INVALID)
  end

  it 'pergunta, valida, grava no contato e segue' do
    customer_says(conversation, 'oi')
    expect(bot_said(conversation)).to eq(['Qual seu e-mail?'])

    customer_says(conversation, 'meu email é Ana@Gmail.com')

    expect(conversation.contact.reload.email).to eq('ana@gmail.com')
    expect(bot_said(conversation).last).to eq('Obrigada!')
    expect(ChatflowExecution.last.context['answers']).to eq('email' => 'ana@gmail.com')
  end

  it 'resposta inválida manda o erro e, esgotadas as tentativas, sai por "inválida"' do
    customer_says(conversation, 'oi')
    customer_says(conversation, 'não tenho')
    expect(bot_said(conversation).last).to eq('Esse e-mail não parece certo.')

    customer_says(conversation, 'sei lá')
    expect(bot_said(conversation).last).to eq('Vou chamar a equipe.')
    expect(ChatflowExecution.last).to be_status_completed
  end
end
