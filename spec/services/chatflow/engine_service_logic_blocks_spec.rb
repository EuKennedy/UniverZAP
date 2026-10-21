require 'rails_helper'

RSpec.describe Chatflow::EngineService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:chatflow) { Chatflow.create!(account: account, name: 'Lógica', inbox: inbox, status: :active, trigger_type: :any_message) }

  describe 'condição se/senão' do
    let!(:vip) { create(:label, account: account, title: 'vip') }

    it 'sai pela porta verdadeira ou falsa' do
      condition = flow_node(chatflow, :condition, 'rules' => [{ 'type' => 'label', 'operator' => 'has', 'label_ids' => [vip.id] }])
      flow_edge(condition, flow_node(chatflow, :send_message, 'text' => 'Oi, VIP!'), 'true')
      flow_edge(condition, flow_node(chatflow, :send_message, 'text' => 'Oi!'), 'false')
      chatflow.update!(start_node: condition)

      customer_says(conversation, 'olá')
      expect(bot_said(conversation)).to eq(['Oi!'])

      other = create(:conversation, account: account, inbox: inbox)
      other.update_labels(['vip'])
      customer_says(other, 'olá')
      expect(bot_said(other)).to eq(['Oi, VIP!'])
      expect(ChatflowExecution.last.context['selections'].first['value']).to eq('true')
    end
  end

  describe 'divisão aleatória' do
    it 'respeita os percentuais (100% sempre no mesmo ramo)' do
      split = flow_node(chatflow, :random_split, 'branches' => [{ 'value' => 'a', 'percent' => 0 }, { 'value' => 'b', 'percent' => 100 }])
      flow_edge(split, flow_node(chatflow, :send_message, 'text' => 'Versão A'), 'a')
      flow_edge(split, flow_node(chatflow, :send_message, 'text' => 'Versão B'), 'b')
      chatflow.update!(start_node: split)

      customer_says(conversation, 'oi')

      expect(bot_said(conversation)).to eq(['Versão B'])
    end

    it 'sorteia pelos pesos' do
      rng = Random.new(42)
      branches = [{ 'value' => 'a', 'percent' => 70 }, { 'value' => 'b', 'percent' => 30 }]
      picks = Array.new(1000) { Chatflow::AutomationBlocks.weighted_pick(branches, rng)['value'] }

      expect(picks.count('a')).to be_between(630, 770)
    end
  end

  describe 'ir para outro fluxo' do
    let(:other) { Chatflow.create!(account: account, name: 'Outro', status: :active, trigger_type: :webhook) }

    before do
      hello = flow_node(other, :send_message, 'text' => 'Bem-vinda ao outro fluxo')
      other.update!(start_node: hello)
      goto = flow_node(chatflow, :goto_flow, 'chatflow_id' => other.id)
      chatflow.update!(start_node: goto)
    end

    it 'encerra este fluxo e começa o outro' do
      customer_says(conversation, 'oi')

      expect(bot_said(conversation)).to eq(['Bem-vinda ao outro fluxo'])
      expect(ChatflowExecution.order(:id).map(&:chatflow_id)).to eq([chatflow.id, other.id])
      expect(ChatflowExecution.last.context['from_chatflow_id']).to eq(chatflow.id)
    end

    it 'não vai para um rascunho' do
      other.update!(status: :draft)
      customer_says(conversation, 'oi')

      expect(bot_said(conversation)).to be_empty
    end
  end

  describe 'digitando…' do
    it 'para alguns segundos e depois segue' do
      typing = flow_node(chatflow, :typing, 'seconds' => 3)
      flow_edge(typing, flow_node(chatflow, :send_message, 'text' => 'Pronto!'))
      chatflow.update!(start_node: typing)

      expect { customer_says(conversation, 'oi') }.to have_enqueued_job(Chatflow::ResumeJob)
      execution = ChatflowExecution.last
      expect(execution).to be_status_waiting_input
      expect(bot_said(conversation)).to be_empty

      customer_says(conversation, 'tem alguém?') # ignorada enquanto digita
      travel 4.seconds do
        Chatflow::ResumeJob.perform_now(execution.id)
      end
      expect(bot_said(conversation)).to eq(['Pronto!'])
    end
  end

  describe 'lista de distribuição' do
    it 'é pulada enquanto o modelo de listas não existe' do
      allow(Chatflow::ListBridge).to receive(:available?).and_return(false)
      list = flow_node(chatflow, :list_action, 'list_id' => 1, 'action' => 'add')
      flow_edge(list, flow_node(chatflow, :send_message, 'text' => 'Segue o fluxo'))
      chatflow.update!(start_node: list)

      customer_says(conversation, 'oi')

      expect(bot_said(conversation)).to eq(['Segue o fluxo'])
    end

    it 'chama a ponte quando o modelo existe' do
      allow(Chatflow::ListBridge).to receive(:available?).and_return(true)
      allow(Chatflow::ListBridge).to receive(:apply)
      chatflow.update!(start_node: flow_node(chatflow, :list_action, 'list_id' => 7, 'action' => 'remove'))

      customer_says(conversation, 'oi')

      expect(Chatflow::ListBridge).to have_received(:apply).with(account, conversation.contact, 7, 'remove')
    end
  end

  it 'marca por onde a execução passou (base do funil)' do
    first = flow_node(chatflow, :send_message, 'text' => 'um')
    second = flow_node(chatflow, :send_message, 'text' => 'dois')
    flow_edge(first, second)
    chatflow.update!(start_node: first)

    customer_says(conversation, 'oi')

    expect(ChatflowExecution.last.visited_node_ids).to eq([first.id, second.id])
  end
end
