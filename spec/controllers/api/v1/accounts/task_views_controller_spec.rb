require 'rails_helper'

RSpec.describe Api::V1::Accounts::TaskViewsController, type: :request do
  let(:account) { create(:account) }
  let(:admin)   { create(:user, account: account, role: :administrator) }
  let(:agent)   { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/:id/task_views' do
    before do
      create(:task_view, account: account, user: agent, name: 'mine')
      create(:task_view, account: account, user: nil,   name: 'shared')
      other_user = create(:user, account: account)
      create(:task_view, account: account, user: other_user, name: 'hidden')
    end

    it 'returns the views visible to the requester' do
      get "/api/v1/accounts/#{account.id}/task_views",
          headers: agent.create_new_auth_token, as: :json
      names = response.parsed_body.map { |v| v['name'] }
      expect(names).to contain_exactly('mine', 'shared')
    end

    it 'returns 401/403/404 for cross-tenant users' do
      foreign = create(:user, account: create(:account), role: :administrator)
      get "/api/v1/accounts/#{account.id}/task_views",
          headers: foreign.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403, 404])
    end
  end

  describe 'POST /api/v1/accounts/:id/task_views' do
    it 'creates a personal view for the requester' do
      expect do
        post "/api/v1/accounts/#{account.id}/task_views",
             params: { task_view: { name: 'mine', filters: { urgency: 'high' } } },
             headers: agent.create_new_auth_token, as: :json
      end.to change(TaskView, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(TaskView.last.user_id).to eq(agent.id)
    end

    it 'lets an admin create a shared view' do
      post "/api/v1/accounts/#{account.id}/task_views",
           params: { task_view: { name: 'team-wide', shared: true } },
           headers: admin.create_new_auth_token, as: :json
      expect(TaskView.last.user_id).to be_nil
    end
  end

  describe 'PATCH /api/v1/accounts/:id/task_views/:id' do
    let(:view) { create(:task_view, account: account, user: agent, name: 'old') }

    it 'lets the owner rename it' do
      patch "/api/v1/accounts/#{account.id}/task_views/#{view.id}",
            params: { task_view: { name: 'new' } },
            headers: agent.create_new_auth_token, as: :json
      expect(view.reload.name).to eq('new')
    end

    it 'forbids unrelated agents from editing' do
      other = create(:user, account: account)
      patch "/api/v1/accounts/#{account.id}/task_views/#{view.id}",
            params: { task_view: { name: 'nope' } },
            headers: other.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403])
    end
  end

  describe 'DELETE /api/v1/accounts/:id/task_views/:id' do
    let!(:view) { create(:task_view, account: account, user: agent) }

    it 'destroys an owned view' do
      expect do
        delete "/api/v1/accounts/#{account.id}/task_views/#{view.id}",
               headers: agent.create_new_auth_token, as: :json
      end.to change(TaskView, :count).by(-1)
    end
  end

  describe 'POST /api/v1/accounts/:id/task_views/:id/set_default' do
    let!(:view_a) { create(:task_view, account: account, user: agent, is_default: true) }
    let(:view_b)  { create(:task_view, account: account, user: agent) }

    it 'sets a new default and clears the previous one' do
      post "/api/v1/accounts/#{account.id}/task_views/#{view_b.id}/set_default",
           headers: agent.create_new_auth_token, as: :json
      expect(view_a.reload.is_default).to be(false)
      expect(view_b.reload.is_default).to be(true)
    end
  end

  describe 'cross-tenant fetch' do
    it 'returns 404 for views from another account' do
      foreign = create(:task_view)
      get "/api/v1/accounts/#{account.id}/task_views/#{foreign.id}",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
