require 'rails_helper'

RSpec.describe Chatflow::Simulator do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:chatflow) { Chatflow.create!(account: account, name: 'Teste', inbox: inbox) }

  let!(:hello) { flow_node(chatflow, :send_message, 'text' => 'Oi, {{ contact.name }}!') }
  let!(:ask) do
    flow_node(chatflow, :question, 'text' => 'Qual seu e-mail?', 'field_type' => 'email', 'error_text' => 'E-mail inválido',
                                   'save_to' => { 'scope' => 'contact', 'key' => 'email' })
  end
  let!(:wait) { flow_node(chatflow, :wait, 'amount' => 1, 'unit' => 'days') }
  let!(:hook) { flow_node(chatflow, :webhook, 'url' => 'https://example.com/hook') }
  let!(:bye) { flow_node(chatflow, :send_message, 'text' => 'Até amanhã!') }

  before do
    chatflow.update!(start_node: hello)
    flow_edge(hello, ask)
    flow_edge(ask, wait)
    flow_edge(wait, hook)
    flow_edge(hook, bye)
  end

  it 'roda o fluxo sem gravar nada nem enviar nada' do
    allow(HTTParty).to receive(:post)

    result = nil
    expect do
      result = described_class.new(chatflow, inputs: ['nao sei', 'ana@gmail.com']).perform
    end.not_to(change { [Message.count, Contact.count, Conversation.count, ChatflowExecution.count] })

    texts = result[:transcript].map { |line| line[:text] || line[:event] }
    expect(texts).to eq(['Oi, Simulated Customer!', 'Qual seu e-mail?', 'nao sei', 'E-mail inválido', 'ana@gmail.com',
                         'waited', 'skipped_webhook', 'Até amanhã!'])
    expect(result[:answers]).to eq('email' => 'ana@gmail.com')
    expect(result[:finished]).to be(true)
    expect(result[:visited_node_ids]).to eq([hello.id, ask.id, wait.id, hook.id, bye.id])
    expect(HTTParty).not_to have_received(:post)
  end

  it 'parado numa pergunta, devolve a etapa atual' do
    result = described_class.new(chatflow).perform

    expect(result[:finished]).to be(false)
    expect(result[:current_node_id]).to eq(ask.id)
  end

  it 'sem etapa inicial avisa' do
    chatflow.update!(start_node: nil)

    expect(described_class.new(chatflow).perform[:error]).to eq('no_start_node')
  end

  it 'a mesma semente sai sempre pelo mesmo ramo do A/B' do
    split = flow_node(chatflow, :random_split, 'branches' => [{ 'value' => 'a', 'percent' => 50 }, { 'value' => 'b', 'percent' => 50 }])
    flow_edge(split, flow_node(chatflow, :send_message, 'text' => 'A'), 'a')
    flow_edge(split, flow_node(chatflow, :send_message, 'text' => 'B'), 'b')
    chatflow.update!(start_node: split)

    runs = Array.new(3) { described_class.new(chatflow, seed: 7).perform[:transcript].first[:text] }
    expect(runs.uniq.size).to eq(1)
  end
end
