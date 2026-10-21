require 'rails_helper'

RSpec.describe 'Chatflow automation API', type: :request do
  let(:account) { create(:account, custom_attributes: { 'vertical_template' => 'ecommerce' }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/chatflows" }

  it 'lista os modelos do vertical e instala um em rascunho' do
    get "#{base}/templates", headers: agent.create_new_auth_token
    expect(response.parsed_body['templates'].pluck('key')).to contain_exactly('ecommerce/rastreio', 'ecommerce/carrinho_abandonado')

    post "#{base}/from_template", params: { key: 'ecommerce/rastreio' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('chatflow', 'status') || response.parsed_body['status']).to eq('draft')
    expect(account.chatflows.last.nodes.count).to eq(6)
  end

  it 'atendente não instala modelo' do
    post "#{base}/from_template", params: { key: 'ecommerce/rastreio' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'opções do editor, funil e simulação' do
    create(:inbox, account: account)
    flow = Chatflow.create!(account: account, name: 'Teste')
    flow.update!(start_node: flow_node(flow, :send_message, 'text' => 'Oi!'))

    get "#{base}/options", headers: admin.create_new_auth_token
    expect(response.parsed_body).to include('lists_available' => false)
    expect(response.parsed_body['chatflows'].pluck('name')).to include('Teste')

    get "#{base}/#{flow.id}/funnel", headers: admin.create_new_auth_token
    expect(response.parsed_body['nodes'].first).to include('node_id' => flow.start_node_id, 'entered' => 0)

    post "#{base}/#{flow.id}/simulate", params: { inputs: [] }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['transcript'].first).to include('type' => 'bot', 'text' => 'Oi!')
  end

  it 'a lista traz as métricas dos últimos 30 dias' do
    flow = Chatflow.create!(account: account, name: 'Com métrica')
    conversation = create(:conversation, account: account)
    ChatflowExecution.create!(account: account, chatflow: flow, conversation: conversation, status: :completed)

    get base, headers: admin.create_new_auth_token
    row = response.parsed_body.find { |f| f['id'] == flow.id }
    expect(row['stats']).to eq('started' => 1, 'completed' => 1, 'live' => 0)
  end

  it 'grava as chaves novas do gatilho' do
    flow = Chatflow.create!(account: account, name: 'Gatilho')
    patch "#{base}/#{flow.id}", params: { chatflow: { trigger_type: 'date', trigger_config: {
      date: { kind: 'birthday', attribute_key: 'aniversario', hour: 10 }, label_ids: [1], pause_on_agent_reply: false, no_reply_minutes: 30
    } } }, headers: admin.create_new_auth_token, as: :json

    expect(flow.reload.date_config).to include('kind' => 'birthday', 'attribute_key' => 'aniversario', 'hour' => 10)
    expect(flow.pause_on_agent_reply?).to be(false)
    expect(flow.no_reply_minutes).to eq(30)
  end
end
