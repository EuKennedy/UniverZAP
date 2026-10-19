require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::WhatsappFlowsController', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:url) { "/api/v1/accounts/#{account.id}/whatsapp_flows" }
  let(:service) { instance_double(Whatsapp::Flows::ManagementService) }

  def ok
    ->(flow) { Whatsapp::Flows::ManagementService::Result.new(success?: true, flow: flow) }
  end

  before do
    allow(Whatsapp::Flows::ManagementService).to receive(:new).and_return(service)
    allow(service).to receive(:push, &ok)
    allow(service).to receive(:publish, &ok)
  end

  it 'lista os modelos do vertical' do
    get "#{url}/templates", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['templates'].map { |t| t['key'] }).to include('beauty_salon/agendamento')
  end

  it 'cria a partir de um modelo e manda para a Meta' do
    post url, params: { whatsapp_flow: { inbox_id: inbox.id, template_key: 'beauty_salon/agendamento' } },
              headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    flow = account.whatsapp_flows.last
    expect(flow.name).to eq('Agendamento')
    expect(flow.category).to eq('APPOINTMENT_BOOKING')
    expect(flow.field_mappings['labels']).to eq(['agendado'])
    expect(service).to have_received(:push).with(flow)
  end

  it 'cria a partir de um Flow JSON colado' do
    json = create(:whatsapp_flow, account: account, inbox: inbox).flow_json
    post url, params: { whatsapp_flow: { inbox_id: inbox.id, name: 'Meu form', category: 'SURVEY', flow_json: json } },
              headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['name']).to eq('Meu form')
    expect(response.parsed_body['flow_json']['screens'].first['id']).to eq('AGENDAMENTO')
  end

  # O rascunho fica salvo com o motivo: o operador corrige e reenvia, em vez
  # de perder o que colou.
  it 'guarda o rascunho e devolve o motivo quando a Meta recusa' do
    allow(service).to receive(:push).and_return(Whatsapp::Flows::ManagementService::Result.new(success?: false, error: 'Invalid Flow JSON'))

    post url, params: { whatsapp_flow: { inbox_id: inbox.id, template_key: 'beauty_salon/agendamento' } },
              headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('Invalid Flow JSON')
    expect(account.whatsapp_flows.count).to eq(1)
  end

  it 'recusa caixa que não é Cloud API' do
    api_inbox = create(:inbox, account: account)
    post url, params: { whatsapp_flow: { inbox_id: api_inbox.id, template_key: 'beauty_salon/agendamento' } },
              headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['error']).to eq('cloud_provider_required')
  end

  it 'deixa o agente listar, mas não criar' do
    create(:whatsapp_flow, account: account, inbox: inbox)

    get url, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body.size).to eq(1)

    post url, params: { whatsapp_flow: { inbox_id: inbox.id, template_key: 'beauty_salon/agendamento' } },
              headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'publica' do
    flow = create(:whatsapp_flow, account: account, inbox: inbox, meta_flow_id: 'f-1')

    post "#{url}/#{flow.id}/publish", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(service).to have_received(:publish).with(flow)
  end
end
