require 'rails_helper'

RSpec.describe 'Api::V2::Kanban::Funnels', type: :request do
  let(:account)     { create(:account) }
  let(:foreign)     { create(:account) }
  let(:read_token)  { KanbanApiToken.generate!(account: account, name: 'r', scopes: ['read:funnels']) }
  let(:write_token) { KanbanApiToken.generate!(account: account, name: 'w', scopes: ['read:funnels', 'write:funnels']) }
  let(:headers_for) { ->(t) { { 'Authorization' => "Bearer #{t.raw_token}" } } }
  let!(:funnel)     { create(:funnel, account: account) }

  describe 'auth + scope enforcement' do
    it 'rejects requests without a token' do
      get '/api/v2/kanban/funnels'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects invalid tokens' do
      get '/api/v2/kanban/funnels', headers: { 'Authorization' => 'Bearer zk_live_bogus' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a write call with a read-only token' do
      post '/api/v2/kanban/funnels', params: { funnel: { name: 'X' } }.to_json,
                                     headers: headers_for.call(read_token).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects a token from a different account that crafts the same URL' do
      foreign_token = KanbanApiToken.generate!(account: foreign, name: 'f', scopes: ['read:funnels'])
      get "/api/v2/kanban/funnels/#{funnel.id}", headers: headers_for.call(foreign_token)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v2/kanban/funnels' do
    it 'returns paginated funnels' do
      create_list(:funnel, 3, account: account)
      get '/api/v2/kanban/funnels', headers: headers_for.call(read_token)
      body = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(body['data'].length).to be >= 4
      expect(body['meta']).to include('page', 'per_page', 'total')
    end
  end

  describe 'POST /api/v2/kanban/funnels' do
    it 'creates a funnel with a write token' do
      expect do
        post '/api/v2/kanban/funnels', params: { funnel: { name: 'New Funnel' } }.to_json,
                                       headers: headers_for.call(write_token).merge('Content-Type' => 'application/json')
      end.to change(account.funnels, :count).by(1)
      expect(response).to have_http_status(:created)
    end
  end

  describe 'PATCH /api/v2/kanban/funnels/:id' do
    it 'updates' do
      patch "/api/v2/kanban/funnels/#{funnel.id}",
            params: { funnel: { name: 'Renamed' } }.to_json,
            headers: headers_for.call(write_token).merge('Content-Type' => 'application/json')
      expect(funnel.reload.name).to eq('Renamed')
    end
  end

  describe 'last_used_at tracking' do
    it 'is updated on every authenticated request' do
      expect do
        get '/api/v2/kanban/funnels', headers: headers_for.call(read_token)
      end.to(change { read_token.reload.last_used_at })
    end
  end
end
