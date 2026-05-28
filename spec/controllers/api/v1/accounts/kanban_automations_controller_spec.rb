require 'rails_helper'

RSpec.describe Api::V1::Accounts::KanbanAutomationsController, type: :request do
  let(:account)  { create(:account) }
  let(:admin)    { create(:user, account: account, role: :administrator) }
  let(:agent)    { create(:user, account: account, role: :agent) }
  let(:funnel)   { create(:funnel, account: account) }
  let(:stage)    { create(:funnel_stage, funnel: funnel) }
  let(:task)     { create(:kanban_task, account: account, funnel: funnel, funnel_stage: stage) }

  describe 'GET /api/v1/accounts/:id/kanban_automations' do
    it 'returns the list for admin' do
      create_list(:kanban_automation, 3, account: account, funnel: funnel)
      get "/api/v1/accounts/#{account.id}/kanban_automations",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.length).to eq(3)
    end

    it 'filters by funnel_id' do
      a1 = create(:kanban_automation, account: account, funnel: funnel)
      _a2 = create(:kanban_automation, account: account, funnel: create(:funnel, account: account))
      get "/api/v1/accounts/#{account.id}/kanban_automations",
          params: { funnel_id: funnel.id },
          headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body.map { |a| a['id'] }).to contain_exactly(a1.id)
    end

    it 'denies cross-tenant access' do
      other_admin = create(:user, account: create(:account), role: :administrator)
      create(:kanban_automation, account: account)
      get "/api/v1/accounts/#{account.id}/kanban_automations",
          headers: other_admin.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403, 404])
    end
  end

  describe 'POST /api/v1/accounts/:id/kanban_automations' do
    let(:valid_params) do
      {
        kanban_automation: {
          name: 'Send WhatsApp on Won',
          event_name: 'task_completed',
          funnel_id: funnel.id,
          conditions: { 'priority_in' => %w[high urgent] },
          actions: [
            { type: 'send_message', params: { content: 'Parabéns!' } }
          ]
        }
      }
    end

    it 'creates the rule for admin' do
      expect do
        post "/api/v1/accounts/#{account.id}/kanban_automations",
             params: valid_params, headers: admin.create_new_auth_token, as: :json
      end.to change(KanbanAutomation, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it 'forbids non-admins' do
      post "/api/v1/accounts/#{account.id}/kanban_automations",
           params: valid_params, headers: agent.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403])
    end

    it 'rejects unknown action types' do
      params = valid_params.deep_dup
      params[:kanban_automation][:actions] = [{ type: 'launch_missiles', params: {} }]
      post "/api/v1/accounts/#{account.id}/kanban_automations",
           params: params, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/:id/kanban_automations/:id' do
    let(:automation) { create(:kanban_automation, account: account, funnel: funnel) }

    it 'updates the rule' do
      patch "/api/v1/accounts/#{account.id}/kanban_automations/#{automation.id}",
            params: { kanban_automation: { active: false } },
            headers: admin.create_new_auth_token, as: :json
      expect(automation.reload.active).to be false
    end
  end

  describe 'DELETE /api/v1/accounts/:id/kanban_automations/:id' do
    let!(:automation) { create(:kanban_automation, account: account, funnel: funnel) }

    it 'destroys the rule' do
      expect do
        delete "/api/v1/accounts/#{account.id}/kanban_automations/#{automation.id}",
               headers: admin.create_new_auth_token, as: :json
      end.to change(KanbanAutomation, :count).by(-1)
    end
  end

  describe 'POST /api/v1/accounts/:id/kanban_automations/:id/test' do
    let(:automation) { create(:kanban_automation, account: account, funnel: funnel) }

    it 'returns a dry-run preview without mutating the task' do
      post "/api/v1/accounts/#{account.id}/kanban_automations/#{automation.id}/test",
           params: { task_id: task.id }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['matched']).to be(true).or be(false)
      expect(body['planned_actions']).to be_an(Array)
    end
  end

  describe 'POST /api/v1/accounts/:id/kanban_automations/:id/run' do
    let(:automation) do
      create(:kanban_automation, account: account, funnel: funnel,
                                  actions: [{ type: 'set_priority', params: { priority: 'urgent' } }])
    end

    it 'executes the rule synchronously' do
      post "/api/v1/accounts/#{account.id}/kanban_automations/#{automation.id}/run",
           params: { task_id: task.id }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(task.reload.priority).to eq('urgent')
    end

    it 'does not run tasks from a different tenant' do
      foreign_task = create(:kanban_task)
      post "/api/v1/accounts/#{account.id}/kanban_automations/#{automation.id}/run",
           params: { task_id: foreign_task.id }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
