require 'rails_helper'

RSpec.describe Api::V1::Accounts::KanbanApiTokensController, type: :request do
  let(:account) { create(:account) }
  let(:admin)   { create(:user, account: account, role: :administrator) }
  let(:agent)   { create(:user, account: account, role: :agent) }

  describe 'POST /api/v1/accounts/:id/kanban_api_tokens' do
    it 'returns the raw token once + persists only the digest' do
      post "/api/v1/accounts/#{account.id}/kanban_api_tokens",
           params: { name: 'CI', scopes: ['read:tasks'] },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['raw_token']).to start_with('zk_live_')
      saved = KanbanApiToken.last
      expect(saved.token_digest).to eq(Digest::SHA256.hexdigest(body['raw_token']))
    end

    it 'forbids non-admins' do
      post "/api/v1/accounts/#{account.id}/kanban_api_tokens",
           params: { name: 'x', scopes: [] },
           headers: agent.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403])
    end
  end

  describe 'POST /api/v1/accounts/:id/kanban_api_tokens/:id/revoke' do
    let!(:token) { KanbanApiToken.generate!(account: account, name: 'r', scopes: []) }

    it 'marks the token as revoked' do
      post "/api/v1/accounts/#{account.id}/kanban_api_tokens/#{token.id}/revoke",
           headers: admin.create_new_auth_token, as: :json
      expect(token.reload.revoked_at).to be_present
    end
  end
end
