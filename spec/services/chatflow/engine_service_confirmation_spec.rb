require 'rails_helper'

RSpec.describe Chatflow::EngineService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:chatflow) { Chatflow.create!(account: account, name: 'SAC', inbox: inbox, status: :active) }

  let!(:confirmation) do
    ChatflowNode.create!(
      chatflow: chatflow, account: account, kind: :confirmation, name: 'Confirmação',
      config: {
        'text' => 'Seu problema foi resolvido?',
        'resolved_keywords' => %w[sim resolveu],
        'unresolved_keywords' => ['não', 'quero humano'],
        'fallback_text' => 'Desculpa, não entendi. Responda com Sim ou Não.'
      }
    )
  end

  let!(:thanks) do
    ChatflowNode.create!(chatflow: chatflow, account: account, kind: :send_message,
                         config: { 'text' => 'Que bom! Até logo.' })
  end

  let!(:to_human) do
    ChatflowNode.create!(chatflow: chatflow, account: account, kind: :send_message,
                         config: { 'text' => 'Vou te passar para um atendente.' })
  end

  let!(:execution) do
    ChatflowExecution.create!(account: account, chatflow: chatflow, conversation: conversation,
                              current_node: confirmation, status: :waiting_input)
  end

  def wire(handle, target)
    ChatflowEdge.create!(chatflow: chatflow, account: account, source_node_id: confirmation.id,
                         target_node_id: target.id, source_handle: handle)
  end

  def customer_says(text)
    message = create(:message, conversation: conversation, account: account,
                               message_type: 'incoming', content: text)
    described_class.new(message).perform
  end

  def bot_said
    conversation.messages.where(message_type: 'outgoing').order(:id).pluck(:content)
  end

  before do
    wire(ChatflowNode::RESOLVED, thanks)
    wire(ChatflowNode::UNRESOLVED, to_human)
  end

  it 'segue pela saída de resolvido' do
    customer_says('sim, resolveu')

    expect(bot_said).to include('Que bom! Até logo.')
  end

  it 'segue pela saída de não resolvido' do
    customer_says('quero humano')

    expect(bot_said).to include('Vou te passar para um atendente.')
  end

  # O menu repergunta para sempre. Numa etapa de fechamento isso prende quem
  # escreveu um desabafo em vez de "sim" num robô que nunca o entende.
  it 'repergunta com a mensagem de não entendi, sem sair do lugar' do
    customer_says('mais ou menos')

    expect(bot_said).to eq(['Desculpa, não entendi. Responda com Sim ou Não.', 'Seu problema foi resolvido?'])
    expect(execution.reload.status).to eq('waiting_input')
    expect(execution.current_node_id).to eq(confirmation.id)
  end

  # Errar para o lado de mandar para um humano é o erro barato; o contrário
  # abandona um cliente que continua com problema.
  it 'desiste depois das tentativas e sai por não resolvido' do
    (ChatflowNode::MAX_CONFIRMATION_RETRIES + 1).times { customer_says('mais ou menos') }

    expect(bot_said).to include('Vou te passar para um atendente.')
  end

  it 'conta as tentativas na execução' do
    customer_says('hein?')

    expect(execution.reload.context.dig('confirmation_tries', confirmation.id.to_s)).to eq(1)
  end

  # Uma resposta certa no meio das tentativas tem que valer.
  it 'aceita a resposta boa depois de uma tentativa perdida' do
    customer_says('mais ou menos')
    customer_says('sim')

    expect(bot_said).to include('Que bom! Até logo.')
  end

  # O operador que não ligou aquela ponta decidiu, por omissão, que acaba ali.
  it 'encerra quando a saída não está ligada em nada' do
    ChatflowEdge.where(chatflow: chatflow).destroy_all

    customer_says('sim')

    expect(execution.reload.status).to eq('completed')
  end

  describe 'a assinatura do fluxo' do
    it 'assina com o nome configurado, em negrito do WhatsApp' do
      chatflow.update!(trigger_config: { 'sender_name' => 'Elisa' })

      customer_says('sim')

      expect(bot_said).to include("*Elisa*\nQue bom! Até logo.")
    end

    # Melhor sem nome do que com um nome inventado por nós.
    it 'não assina nada quando o nome está em branco' do
      customer_says('sim')

      expect(bot_said).to include('Que bom! Até logo.')
    end
  end
end
