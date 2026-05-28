require 'rails_helper'

RSpec.describe 'Api::V2::Kanban::Tasks', type: :request do
  let(:account)     { create(:account) }
  let(:write_token) { KanbanApiToken.generate!(account: account, name: 'w', scopes: ['read:tasks', 'write:tasks']) }
  let(:funnel)      { create(:funnel, account: account) }
  let(:stage)       { create(:funnel_stage, funnel: funnel) }
  let(:other_stage) { create(:funnel_stage, funnel: funnel, name: 'Other') }
  let(:other_funnel) { create(:funnel, account: account) }
  let(:other_funnel_stage) { create(:funnel_stage, funnel: other_funnel) }
  let(:headers) { { 'Authorization' => "Bearer #{write_token.raw_token}", 'Content-Type' => 'application/json' } }
  let!(:task)   { create(:kanban_task, account: account, funnel: funnel, funnel_stage: stage, title: 'Greenfield', priority: :high) }

  describe 'GET /api/v2/kanban/tasks (with filters)' do
    before do
      create(:kanban_task, account: account, funnel: funnel, funnel_stage: stage, title: 'Lowprio', priority: :low)
    end

    it 'filters by funnel_id' do
      get '/api/v2/kanban/tasks', params: { funnel_id: funnel.id }, headers: headers
      expect(response.parsed_body['data'].length).to eq(2)
    end

    it 'filters by priority' do
      get '/api/v2/kanban/tasks', params: { priority: 'high' }, headers: headers
      data = response.parsed_body['data']
      expect(data.length).to eq(1)
      expect(data.first['title']).to eq('Greenfield')
    end

    it 'filters by title query' do
      get '/api/v2/kanban/tasks', params: { q: 'greenfield' }, headers: headers
      data = response.parsed_body['data']
      expect(data.length).to eq(1)
    end
  end

  describe 'POST /api/v2/kanban/tasks' do
    it 'creates a task in the specified funnel/stage' do
      expect do
        post '/api/v2/kanban/tasks',
             params: { funnel_id: funnel.id, funnel_stage_id: stage.id, task: { title: 'API created' } }.to_json,
             headers: headers
      end.to change(funnel.kanban_tasks, :count).by(1)
      expect(response).to have_http_status(:created)
    end
  end

  describe 'POST /api/v2/kanban/tasks/:id/move' do
    it 'moves within the same funnel' do
      post "/api/v2/kanban/tasks/#{task.id}/move",
           params: { funnel_stage_id: other_stage.id }.to_json,
           headers: headers
      expect(task.reload.funnel_stage_id).to eq(other_stage.id)
    end

    it 'moves across funnels' do
      post "/api/v2/kanban/tasks/#{task.id}/move",
           params: { funnel_id: other_funnel.id, funnel_stage_id: other_funnel_stage.id }.to_json,
           headers: headers
      task.reload
      expect(task.funnel_id).to eq(other_funnel.id)
      expect(task.funnel_stage_id).to eq(other_funnel_stage.id)
    end

    it 'returns 400 with no movement params' do
      post "/api/v2/kanban/tasks/#{task.id}/move", params: {}.to_json, headers: headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'cross-tenant isolation' do
    it 'returns 404 when the task belongs to another account' do
      foreign = create(:kanban_task)
      get "/api/v2/kanban/tasks/#{foreign.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
