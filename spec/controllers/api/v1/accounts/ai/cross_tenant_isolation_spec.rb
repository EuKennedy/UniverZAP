# frozen_string_literal: true

require 'rails_helper'

# Multi-tenant isolation guard. Every UniverZAP-specific endpoint scopes
# its reads/writes via `Current.account.<association>`, so a request
# made against /api/v1/accounts/A/... with an auth token belonging to
# account B should either route to the auth'd user's own account or
# 401/404. The previous Chatwoot OSS coverage doesn't reach the new
# Athenas + Funnels + Kanban endpoints, so we add a focused sweep here
# to nail the contract down.
RSpec.describe 'Cross-tenant isolation for UniverZAP endpoints', type: :request do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:admin_a) { create(:user, account: account_a, role: :administrator) }
  let(:admin_b) { create(:user, account: account_b, role: :administrator) }

  describe 'Ai::AssistantsController' do
    let!(:assistant_b) { create(:ai_assistant, account: account_b) }

    it 'returns 404 when account A admin tries to fetch an assistant owned by account B' do
      get "/api/v1/accounts/#{account_a.id}/ai/assistants/#{assistant_b.id}",
          headers: admin_a.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401/403 when admin B tries to fetch via /accounts/A/...' do
      get "/api/v1/accounts/#{account_a.id}/ai/assistants",
          headers: admin_b.create_new_auth_token, as: :json

      expect(response.status).to be_in([401, 403, 404])
    end

    it 'never leaks account B assistants through the index of account A' do
      create(:ai_assistant, account: account_a, name: 'Mine')
      get "/api/v1/accounts/#{account_a.id}/ai/assistants",
          headers: admin_a.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      ids = body['payload'].map { |row| row['id'] } if body['payload']
      expect(ids).not_to include(assistant_b.id) if ids
    end
  end

  describe 'Ai::CreditsController' do
    it 'returns the credits for the auth\'d account only' do
      get "/api/v1/accounts/#{account_a.id}/ai/credits",
          headers: admin_a.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include('balance_cents_brl', 'threshold_status', 'packages')
    end

    it 'returns 401/403/404 when account B admin hits account A credits endpoint' do
      get "/api/v1/accounts/#{account_a.id}/ai/credits",
          headers: admin_b.create_new_auth_token, as: :json

      expect(response.status).to be_in([401, 403, 404])
    end
  end

  describe 'FunnelsController' do
    let!(:funnel_b) { create(:funnel, account: account_b) }

    it 'returns 404 when account A admin tries to fetch funnel owned by B' do
      get "/api/v1/accounts/#{account_a.id}/funnels/#{funnel_b.id}",
          headers: admin_a.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401/403/404 when admin B hits /accounts/A/funnels' do
      get "/api/v1/accounts/#{account_a.id}/funnels",
          headers: admin_b.create_new_auth_token, as: :json

      expect(response.status).to be_in([401, 403, 404])
    end
  end

  describe 'Kanban tasks endpoint scope' do
    let!(:funnel_b) { create(:funnel, account: account_b) }
    let!(:stage_b) { create(:funnel_stage, funnel: funnel_b, account: account_b) }
    let!(:task_b) { create(:kanban_task, funnel: funnel_b, funnel_stage: stage_b, account: account_b) }

    it 'returns 404 when account A admin asks for funnel B tasks' do
      get "/api/v1/accounts/#{account_a.id}/funnels/#{funnel_b.id}/kanban_tasks",
          headers: admin_a.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
