# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Ai::CustomToolsController', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:ai_assistant, account: account) }

  # `as_user` is a plain positional (not a keyword) so the trailing attrs hash
  # is passed as the first positional under Ruby 3's keyword separation.
  def create_tool(attrs, as_user = admin)
    post "/api/v1/accounts/#{account.id}/ai/assistants/#{assistant.id}/custom_tools",
         params: { ai_custom_tool: attrs }, headers: as_user.create_new_auth_token, as: :json
  end

  it 'creates a tool scoped to the agent' do
    expect do
      create_tool(title: 'Buscar', endpoint_url: 'https://loja.example.com/api',
                  http_method: 'GET', auth_type: 'none', param_schema: [])
    end.to change { assistant.custom_tools.count }.by(1)

    expect(response).to have_http_status(:success)
  end

  # The credentials go in write-only: they must never be echoed back to the UI.
  it 'never returns the auth credentials' do
    create_tool(title: 'Buscar', endpoint_url: 'https://loja.example.com/api', http_method: 'GET',
                auth_type: 'basic', auth_config: { username: 'u', password: 'segredo' }, param_schema: [])

    expect(response.parsed_body).not_to have_key('auth_config')
    expect(response.body).not_to include('segredo')
  end

  it 'is administrator-only' do
    create_tool({ title: 'x', endpoint_url: 'https://loja.example.com/api' }, agent)

    expect(response).to have_http_status(:unauthorized)
  end
end
