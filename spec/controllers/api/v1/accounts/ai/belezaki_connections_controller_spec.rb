# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Ai::BelezakiConnectionsController', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/ai/assistants/#{assistant.id}/belezaki_connection" }

  # Doubled at the class rather than any-instance: the controller builds its own
  # service, and this is the seam that lets the request spec stay about the HTTP
  # contract instead of about belezaki being reachable.
  def stub_connect(result = nil, error: nil)
    service = instance_double(Ai::Belezaki::ConnectService)
    allow(Ai::Belezaki::ConnectService).to receive(:new).and_return(service)
    if error
      allow(service).to receive(:perform).and_raise(error)
    else
      allow(service).to receive(:perform).and_return(result)
    end
  end

  def connect(as_user = admin)
    post url, headers: as_user.create_new_auth_token, as: :json
  end

  it 'connects and names the salon' do
    stub_connect(Ai::Belezaki::Connection.new(salon_name: 'Studio Bella', status: 'active'))

    connect

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['connection']['salon_name']).to eq('Studio Bella')
  end

  # Connecting an agenda decides where every customer this agent talks to ends
  # up booked.
  it 'is administrator-only' do
    connect(agent)

    expect(response).to have_http_status(:unauthorized)
  end

  # The operator has to be told WHICH thing is wrong: "not linked" is their
  # onboarding, "not configured" is ours, and the two have different fixes.
  it 'reports the reason it could not connect' do
    stub_connect(error: Ai::Belezaki::ConnectService::NotLinked)

    connect

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('not_linked')
  end

  it 'reports a refusal to hold two agendas at once' do
    stub_connect(error: Ai::Belezaki::ConnectService::AgendaTaken)

    connect

    expect(response.parsed_body['error']).to eq('agenda_taken')
  end

  # A salon that answered something we cannot act on must not read as a bug in
  # the dashboard, and its wording must not reach the screen.
  it 'reports a failed probe without leaking the salon message' do
    stub_connect(error: Ai::Belezaki::AgentClient::Error.new('Salão não encontrado', code: 'http_404'))

    connect

    expect(response.parsed_body['error']).to eq('probe_failed')
    expect(response.body).not_to include('Salão não encontrado')
  end

  it 'reads back nothing when the agent has no connection' do
    get url, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['connection']).to be_nil
  end

  it 'unbinds on disconnect' do
    Ai::Belezaki::Connection.create!(ai_assistant: assistant, account: account, external_id: 'ext-1')

    delete url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(assistant.reload.belezaki_connection).to be_nil
  end

  # Another workspace's agent is not addressable from this account, whatever id
  # is typed into the URL.
  it 'cannot reach an agent from another account' do
    other = create(:ai_assistant, account: create(:account))

    post "/api/v1/accounts/#{account.id}/ai/assistants/#{other.id}/belezaki_connection",
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
