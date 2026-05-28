require 'rails_helper'

RSpec.describe 'Api::V2::Tasks', type: :request do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:write_token) do
    KanbanApiToken.generate!(account: account, name: 'w', scopes: ['read:user_tasks', 'write:user_tasks'])
  end
  let(:read_only_token) do
    KanbanApiToken.generate!(account: account, name: 'r', scopes: ['read:user_tasks'])
  end
  let(:headers) { { 'Authorization' => "Bearer #{write_token.raw_token}", 'Content-Type' => 'application/json' } }
  let(:read_headers) { { 'Authorization' => "Bearer #{read_only_token.raw_token}" } }
  let!(:task) { create(:task, account: account, created_by_user: user, title: 'Greenfield', urgency: :high) }

  describe 'authentication' do
    it 'rejects a missing token' do
      get '/api/v2/tasks'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects an invalid token' do
      get '/api/v2/tasks', headers: { 'Authorization' => 'Bearer zk_live_garbage' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects revoked tokens' do
      write_token.revoke!
      get '/api/v2/tasks', headers: headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'scope enforcement' do
    it 'allows reads with read:user_tasks' do
      get '/api/v2/tasks', headers: read_headers
      expect(response).to have_http_status(:ok)
    end

    it 'forbids writes with read-only scope' do
      post '/api/v2/tasks', params: { task: { title: 'x' } }.to_json,
                            headers: read_headers.merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v2/tasks' do
    before do
      create(:task, account: account, created_by_user: user, title: 'Other', urgency: :low)
    end

    it 'paginates with a meta envelope' do
      get '/api/v2/tasks', headers: headers
      body = response.parsed_body
      expect(body).to include('data', 'meta')
      expect(body['meta']).to include('page', 'per_page', 'total', 'total_pages')
      expect(body['data'].length).to eq(2)
    end

    it 'filters by urgency' do
      get '/api/v2/tasks', params: { urgency: 'high' }, headers: headers
      expect(response.parsed_body['data'].map { |t| t['title'] }).to eq(['Greenfield'])
    end

    it 'filters by status' do
      task.update!(status: :done)
      get '/api/v2/tasks', params: { status: 'done' }, headers: headers
      expect(response.parsed_body['data'].length).to eq(1)
    end

    it 'searches by title' do
      get '/api/v2/tasks', params: { q: 'green' }, headers: headers
      expect(response.parsed_body['data'].length).to eq(1)
    end
  end

  describe 'CRUD via Bearer' do
    it 'creates a task' do
      expect do
        post '/api/v2/tasks',
             params: { task: { title: 'API created' } }.to_json,
             headers: headers
      end.to change(account.tasks, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it 'updates a task' do
      put "/api/v2/tasks/#{task.id}",
          params: { task: { title: 'edited' } }.to_json,
          headers: headers
      expect(task.reload.title).to eq('edited')
    end

    it 'destroys a task' do
      expect do
        delete "/api/v2/tasks/#{task.id}", headers: headers
      end.to change(Task, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it 'completes a task' do
      post "/api/v2/tasks/#{task.id}/complete", params: {}.to_json, headers: headers
      task.reload
      expect(task.status).to eq('done')
      expect(task.completed_at).not_to be_nil
    end

    it 'assigns a user' do
      assignee = create(:user, account: account)
      expect do
        post "/api/v2/tasks/#{task.id}/assign",
             params: { user_id: assignee.id }.to_json, headers: headers
      end.to change(task.task_assignees, :count).by(1)
    end
  end

  describe 'cross-tenant isolation' do
    it 'returns 404 for tasks belonging to another account' do
      foreign = create(:task)
      get "/api/v2/tasks/#{foreign.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
