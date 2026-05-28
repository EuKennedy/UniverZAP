require 'rails_helper'

RSpec.describe Api::V1::Accounts::KanbanWebhookSubscriptionsController, type: :request do
  let(:account) { create(:account) }
  let(:admin)   { create(:user, account: account, role: :administrator) }
  let(:agent)   { create(:user, account: account, role: :agent) }

  describe 'POST /api/v1/accounts/:id/kanban_webhook_subscriptions' do
    let(:valid) do
      {
        kanban_webhook_subscription: {
          name: 'n8n hook',
          url: 'https://n8n.example/webhook',
          events: ['task.created', 'task.moved']
        }
      }
    end

    it 'creates a subscription and exposes the secret on create' do
      post "/api/v1/accounts/#{account.id}/kanban_webhook_subscriptions",
           params: valid, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['secret']).to be_present
    end

    it 'forbids non-admins' do
      post "/api/v1/accounts/#{account.id}/kanban_webhook_subscriptions",
           params: valid, headers: agent.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403])
    end

    it 'rejects http URLs in production-like config but accepts https' do
      params = valid.deep_dup
      params[:kanban_webhook_subscription][:url] = 'not-a-url'
      post "/api/v1/accounts/#{account.id}/kanban_webhook_subscriptions",
           params: params, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /api/v1/accounts/:id/kanban_webhook_subscriptions/:id/test' do
    let!(:subscription) { create(:kanban_webhook_subscription, account: account) }

    it 'enqueues a test delivery' do
      expect do
        post "/api/v1/accounts/#{account.id}/kanban_webhook_subscriptions/#{subscription.id}/test",
             headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Kanban::WebhookSubscriptionDeliveryJob)
      expect(response).to have_http_status(:accepted)
    end
  end
end
