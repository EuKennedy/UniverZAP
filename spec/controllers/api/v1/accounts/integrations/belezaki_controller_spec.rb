require 'rails_helper'

RSpec.describe 'Belezaki Integration API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, phone_number: '+5531984956383') }

  describe 'GET /api/v1/accounts/:account_id/integrations/belezaki/customer' do
    let(:url) { "/api/v1/accounts/#{account.id}/integrations/belezaki/customer" }

    it 'returns unauthorized without a session' do
      get url, params: { contact_id: contact.id }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the salon card of the contact for an agent of the account' do
      card = { status: 'ok', client: { 'name' => 'Maria' }, next: nil, upcoming: [], history: [] }
      service = instance_double(Belezaki::CustomerCardService, perform: card)
      allow(Belezaki::CustomerCardService).to receive(:new).with(account: account, contact: contact).and_return(service)

      get url, params: { contact_id: contact.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('status' => 'ok', 'client' => { 'name' => 'Maria' })
    end

    it 'does not reach a contact of another account' do
      other_contact = create(:contact, phone_number: '+5531999999999')

      get url, params: { contact_id: other_contact.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/integrations/belezaki/catalog' do
    it 'serves the salon catalogue to any agent of the account' do
      catalog = { status: 'ok', services: [{ 'name' => 'Corte' }], professionals: [] }
      allow(Belezaki::CatalogService).to receive(:new).with(account: account)
                                                      .and_return(instance_double(Belezaki::CatalogService, perform: catalog))

      get "/api/v1/accounts/#{account.id}/integrations/belezaki/catalog", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['services'].pluck('name')).to eq(%w[Corte])
    end
  end

  describe 'POST /api/v1/accounts/:account_id/integrations/belezaki/sync_catalog' do
    let(:url) { "/api/v1/accounts/#{account.id}/integrations/belezaki/sync_catalog" }

    it 'is for administrators only' do
      post url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refreshes the catalogue and syncs the attributes for an administrator' do
      admin = create(:user, account: account, role: :administrator)
      catalog = { status: 'ok', services: [], professionals: [] }
      allow(Belezaki::CatalogService).to receive(:new).with(account: account, refresh: true)
                                                      .and_return(instance_double(Belezaki::CatalogService, perform: catalog))
      allow(Belezaki::CatalogSyncService).to receive(:new).with(account: account, catalog: catalog)
                                                          .and_return(instance_double(Belezaki::CatalogSyncService,
                                                                                      perform: { synced: true, services: 0, professionals: 0 }))

      post url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('status' => 'ok', 'sync' => include('synced' => true))
    end
  end
end
