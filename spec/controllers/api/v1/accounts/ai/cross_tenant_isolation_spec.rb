# frozen_string_literal: true

require 'rails_helper'

# Multi-tenant isolation guard. Every UniverZAP-specific endpoint scopes
# its reads/writes via `Current.account.<association>`, so a request
# made against /api/v1/accounts/A/... with an auth token belonging to
# account B should either route to the auth'd user's own account or
# 401/404. The previous Chatwoot OSS coverage doesn't reach the new
# Athenas + Funnels endpoints, so we add a focused sweep here to nail
# the contract down. Kanban tasks routing is exercised via the funnel
# scope guarantee — funnel B must 404 for account A, so kanban under
# it is unreachable by definition.
RSpec.describe 'Cross-tenant isolation for UniverZAP endpoints', type: :request do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:admin_a) { create(:user, account: account_a, role: :administrator) }
  let(:admin_b) { create(:user, account: account_b, role: :administrator) }

  describe 'Ai::AssistantsController' do
    let(:assistant_b) { create(:ai_assistant, account: account_b) }

    before { assistant_b }

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
      body = response.parsed_body
      ids = body['payload'].map { |row| row['id'] } if body['payload']
      expect(ids).not_to include(assistant_b.id) if ids
    end
  end

  describe 'Ai::CreditsController' do
    it 'returns the credits for the auth\'d account only' do
      get "/api/v1/accounts/#{account_a.id}/ai/credits",
          headers: admin_a.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include('balance_cents_brl', 'threshold_status', 'packages')
    end

    it 'returns 401/403/404 when account B admin hits account A credits endpoint' do
      get "/api/v1/accounts/#{account_a.id}/ai/credits",
          headers: admin_b.create_new_auth_token, as: :json

      expect(response.status).to be_in([401, 403, 404])
    end
  end

  describe 'FunnelsController' do
    let(:funnel_b) { create(:funnel, account: account_b) }

    before { funnel_b }

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

  # Regression guard for the cross-tenant assistant-bind hole: an account must
  # never be able to attach another account's Ai::Assistant to its inbox /
  # conversation, and the autopilot job must never answer with a foreign
  # assistant even if a bad row slipped through. Covers the EXECUTION path (the
  # REST index/show sweep above did not reach it).
  describe 'AI assistant cross-tenant binding (execution path)' do
    let(:assistant_b) { create(:ai_assistant, account: account_b) }

    before { assistant_b }

    it 'rejects binding a cross-account assistant to an inbox (model backstop)' do
      inbox = create(:inbox, account: account_a)
      expect(inbox.update(ai_assistant: assistant_b)).to be(false)
      expect(inbox.errors[:ai_assistant]).to be_present
      expect(inbox.reload.ai_assistant_id).to be_nil
    end

    it 'rejects binding a cross-account assistant to a conversation (model backstop)' do
      conversation = create(:conversation, account: account_a)
      expect(conversation.update(ai_assistant: assistant_b)).to be(false)
      expect(conversation.errors[:ai_assistant]).to be_present
      expect(conversation.reload.ai_assistant_id).to be_nil
    end

    it 'still allows binding an assistant owned by the same account' do
      inbox = create(:inbox, account: account_a)
      own = create(:ai_assistant, account: account_a)
      expect(inbox.update(ai_assistant: own)).to be(true)
    end

    it 'refuses via the API to bind account B assistant to an account A inbox' do
      inbox = create(:inbox, account: account_a)
      patch "/api/v1/accounts/#{account_a.id}/inboxes/#{inbox.id}",
            params: { ai_assistant_id: assistant_b.id },
            headers: admin_a.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(inbox.reload.ai_assistant_id).to be_nil
    end

    it 'refuses via the API to bind account B assistant to an account A conversation' do
      conversation = create(:conversation, account: account_a)
      patch "/api/v1/accounts/#{account_a.id}/conversations/#{conversation.display_id}",
            params: { ai_assistant_id: assistant_b.id },
            headers: admin_a.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(conversation.reload.ai_assistant_id).to be_nil
    end

    it 'the autopilot job refuses to reply with an assistant from another account' do
      conversation = create(:conversation, account: account_a)
      message = create(:message, conversation: conversation, account: account_a, inbox: conversation.inbox)

      expect(Ai::AutopilotReplyService).not_to receive(:new)
      expect do
        Ai::AutopilotReplyJob.perform_now(message.id, assistant_b.id)
      end.not_to(change { conversation.reload.messages.count })
    end
  end
end
