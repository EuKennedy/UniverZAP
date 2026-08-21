require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::WhatsappTemplatesController', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:url) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsapp_templates" }
  let(:service) { instance_double(Whatsapp::TemplateManagementService) }

  def ok(payload)
    Whatsapp::TemplateManagementService::Result.new(success?: true, template: payload)
  end

  before { allow(Whatsapp::TemplateManagementService).to receive(:new).and_return(service) }

  it 'lista os templates da caixa' do
    allow(service).to receive(:list).and_return(ok([{ name: 'promo', status: 'APPROVED' }]))

    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['template'].first['status']).to eq('APPROVED')
  end

  it 'submete um template novo' do
    allow(service).to receive(:create).and_return(ok({ name: 'promo', status: 'PENDING' }))

    post url, params: { template: { name: 'promo', category: 'UTILITY', language: 'pt_BR', body: 'Oi.' } },
              headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(service).to have_received(:create).with(hash_including(name: 'promo', category: 'UTILITY'))
  end

  # 422 e não 502: o que volta é quase sempre algo que o operador escreveu, e é
  # ele quem corrige.
  it 'devolve o motivo da recusa como erro do pedido' do
    allow(service).to receive(:create).and_return(
      Whatsapp::TemplateManagementService::Result.new(success?: false, error: 'name_format')
    )

    post url, params: { template: { name: 'Promo', category: 'UTILITY', language: 'pt_BR', body: 'Oi.' } },
              headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('name_format')
  end

  # Recusa repetida derruba a qualidade do número, e a qualidade define o limite
  # diário de envio da conta inteira.
  it 'recusa um agente comum' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  # WAHA é API não oficial e não tem template. Dizer isso é melhor do que chamar
  # a Meta com credencial que não existe.
  it 'explica que uma caixa WAHA não tem template' do
    waha = create(:channel_whatsapp, account: account, provider: 'waha',
                                     validate_provider_config: false, sync_templates: false)

    get "/api/v1/accounts/#{account.id}/inboxes/#{waha.inbox.id}/whatsapp_templates",
        headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('cloud_provider_required')
  end

  # A caixa de outro workspace responde 404 igual a uma que não existe, mesmo
  # com o id certo na URL.
  it 'não alcança a caixa de outra conta' do
    other = create(:channel_whatsapp, account: create(:account), provider: 'whatsapp_cloud',
                                      validate_provider_config: false, sync_templates: false)

    get "/api/v1/accounts/#{account.id}/inboxes/#{other.inbox.id}/whatsapp_templates",
        headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
