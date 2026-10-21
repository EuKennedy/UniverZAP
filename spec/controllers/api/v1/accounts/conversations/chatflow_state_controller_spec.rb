require 'rails_helper'

RSpec.describe 'Conversation chatflow state API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/chatflow_state" }
  let(:chatflow) { Chatflow.create!(account: account, name: 'SAC', inbox: inbox, status: :active, trigger_type: :any_message) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    chatflow.update!(start_node: flow_node(chatflow, :menu, 'text' => 'Escolha', 'options' => [{ 'label' => 'A', 'value' => 'a' }]))
    customer_says(conversation, 'oi')
  end

  it 'mostra o fluxo em andamento, pausa e retoma' do
    get url, headers: agent.create_new_auth_token
    expect(response.parsed_body).to include('paused' => false)
    expect(response.parsed_body['execution']).to include('chatflow_name' => 'SAC', 'status' => 'waiting_input', 'node_kind' => 'menu')

    post "#{url}/pause", headers: agent.create_new_auth_token
    expect(response.parsed_body).to include('paused' => true, 'paused_by' => agent.name)
    expect(response.parsed_body['execution']['status']).to eq('paused')

    post "#{url}/resume", headers: agent.create_new_auth_token
    expect(response.parsed_body).to include('paused' => false)
    expect(response.parsed_body['execution']['status']).to eq('waiting_input')
  end

  it 'quem não é da caixa não vê' do
    outsider = create(:user, account: account, role: :agent)
    get url, headers: outsider.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end
end
