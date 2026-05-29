require 'rails_helper'

RSpec.describe Api::V1::Accounts::TasksController, type: :request do
  let(:account) { create(:account) }
  let(:admin)   { create(:user, account: account, role: :administrator) }
  let(:agent)   { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/:id/tasks' do
    before do
      create_list(:task, 3, account: account, created_by_user: admin)
    end

    it 'lists tasks for an admin' do
      get "/api/v1/accounts/#{account.id}/tasks",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.length).to eq(3)
    end

    it 'filters by status' do
      create(:task, account: account, created_by_user: admin, status: :done)
      get "/api/v1/accounts/#{account.id}/tasks",
          params: { status: 'done' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body.length).to eq(1)
    end

    it 'returns 401/403/404 for cross-tenant users' do
      other_admin = create(:user, account: create(:account), role: :administrator)
      get "/api/v1/accounts/#{account.id}/tasks",
          headers: other_admin.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403, 404])
    end
  end

  describe 'POST /api/v1/accounts/:id/tasks' do
    it 'creates a task as admin' do
      expect do
        post "/api/v1/accounts/#{account.id}/tasks",
             params: { task: { title: 'Ship T1' } },
             headers: admin.create_new_auth_token, as: :json
      end.to change(Task, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it 'sets created_by_user from current user' do
      post "/api/v1/accounts/#{account.id}/tasks",
           params: { task: { title: 'mine' } },
           headers: agent.create_new_auth_token, as: :json
      expect(Task.last.created_by_user_id).to eq(agent.id)
    end
  end

  describe 'PATCH /api/v1/accounts/:id/tasks/:id' do
    let!(:task) { create(:task, account: account, created_by_user: admin) }

    it 'updates the title' do
      patch "/api/v1/accounts/#{account.id}/tasks/#{task.id}",
            params: { task: { title: 'updated' } },
            headers: admin.create_new_auth_token, as: :json
      expect(task.reload.title).to eq('updated')
    end

    it 'forbids unrelated agents' do
      patch "/api/v1/accounts/#{account.id}/tasks/#{task.id}",
            params: { task: { title: 'nope' } },
            headers: agent.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403])
    end
  end

  describe 'DELETE /api/v1/accounts/:id/tasks/:id' do
    let!(:task) { create(:task, account: account, created_by_user: admin) }

    it 'destroys the task' do
      expect do
        delete "/api/v1/accounts/#{account.id}/tasks/#{task.id}",
               headers: admin.create_new_auth_token, as: :json
      end.to change(Task, :count).by(-1)
    end
  end

  describe 'POST /api/v1/accounts/:id/tasks/:id/assign' do
    let(:task)     { create(:task, account: account, created_by_user: admin) }
    let(:assignee) { create(:user, account: account) }

    it 'creates an assignee' do
      expect do
        post "/api/v1/accounts/#{account.id}/tasks/#{task.id}/assign",
             params: { user_id: assignee.id },
             headers: admin.create_new_auth_token, as: :json
      end.to change(task.task_assignees, :count).by(1)
    end

    it 'rejects users from other accounts' do
      foreign = create(:user, account: create(:account))
      post "/api/v1/accounts/#{account.id}/tasks/#{task.id}/assign",
           params: { user_id: foreign.id },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/accounts/:id/tasks/:id/assignees/:user_id' do
    let(:task)     { create(:task, account: account, created_by_user: admin) }
    let(:assignee) { create(:user, account: account) }

    before { task.task_assignees.create!(user: assignee) }

    it 'removes the assignee' do
      expect do
        delete "/api/v1/accounts/#{account.id}/tasks/#{task.id}/assignees/#{assignee.id}",
               headers: admin.create_new_auth_token, as: :json
      end.to change(task.task_assignees, :count).by(-1)
    end
  end

  describe 'POST /api/v1/accounts/:id/tasks/:id/complete' do
    let(:task) { create(:task, account: account, created_by_user: admin) }

    it 'sets status=done and completed_at' do
      freeze_time do
        post "/api/v1/accounts/#{account.id}/tasks/#{task.id}/complete",
             headers: admin.create_new_auth_token, as: :json
        task.reload
        expect(task.status).to eq('done')
        expect(task.completed_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe 'POST /api/v1/accounts/:id/tasks/:id/comments' do
    let(:task) { create(:task, account: account, created_by_user: admin) }

    it 'creates a comment' do
      expect do
        post "/api/v1/accounts/#{account.id}/tasks/#{task.id}/comments",
             params: { body: { type: 'doc', content: 'hello' } },
             headers: admin.create_new_auth_token, as: :json
      end.to change(task.task_comments, :count).by(1)
      expect(response).to have_http_status(:created)
    end
  end

  describe 'GET /api/v1/accounts/:id/tasks/:id/activities' do
    let(:task) { create(:task, account: account, created_by_user: admin) }

    it 'returns paginated activities' do
      get "/api/v1/accounts/#{account.id}/tasks/#{task.id}/activities",
          headers: admin.create_new_auth_token, as: :json
      body = response.parsed_body
      expect(body).to include('data', 'meta')
      expect(body['meta']).to include('page', 'per_page', 'total')
    end
  end

  describe 'cross-tenant fetch' do
    it 'returns 404 for tasks from another account' do
      foreign = create(:task)
      get "/api/v1/accounts/#{account.id}/tasks/#{foreign.id}",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/:id/tasks/bulk' do
    let!(:tasks) { create_list(:task, 3, account: account, created_by_user: admin) }

    it 'completes multiple tasks' do
      post "/api/v1/accounts/#{account.id}/tasks/bulk",
           params: { task_ids: tasks.map(&:id), action: 'complete' },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['ok']).to eq(3)
      tasks.each { |t| expect(t.reload.status).to eq('done') }
    end

    it 'deletes multiple tasks' do
      expect do
        post "/api/v1/accounts/#{account.id}/tasks/bulk",
             params: { task_ids: tasks.map(&:id), action: 'delete' },
             headers: admin.create_new_auth_token, as: :json
      end.to change(Task, :count).by(-3)
      expect(response.parsed_body['ok']).to eq(3)
    end

    it 'assigns multiple tasks to a user' do
      assignee = create(:user, account: account)
      post "/api/v1/accounts/#{account.id}/tasks/bulk",
           params: { task_ids: tasks.map(&:id), action: 'assign', payload: { user_id: assignee.id } },
           headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['ok']).to eq(3)
      expect(tasks.first.reload.assignees.pluck(:id)).to include(assignee.id)
    end

    it 'sets urgency on multiple tasks' do
      post "/api/v1/accounts/#{account.id}/tasks/bulk",
           params: { task_ids: tasks.map(&:id), action: 'set_urgency', payload: { urgency: 'high' } },
           headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['ok']).to eq(3)
      expect(tasks.first.reload.urgency).to eq('high')
    end

    it 'returns 422 for unknown actions' do
      post "/api/v1/accounts/#{account.id}/tasks/bulk",
           params: { task_ids: tasks.map(&:id), action: 'unknown' },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'reports missing ids as failures' do
      post "/api/v1/accounts/#{account.id}/tasks/bulk",
           params: { task_ids: tasks.map(&:id) + [999_999], action: 'complete' },
           headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['failed'].map { |r| r['reason'] }).to include('not_found')
    end
  end

  describe 'GET /api/v1/accounts/:id/tasks/team_workload' do
    before { create_list(:task, 2, account: account, created_by_user: admin) }

    it 'returns workload payload for admins' do
      get "/api/v1/accounts/#{account.id}/tasks/team_workload",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('agents', 'totals')
    end

    it 'forbids non-admins' do
      get "/api/v1/accounts/#{account.id}/tasks/team_workload",
          headers: agent.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403])
    end

    it 'returns 404 for cross-tenant accounts' do
      foreign_admin = create(:user, account: create(:account), role: :administrator)
      get "/api/v1/accounts/#{account.id}/tasks/team_workload",
          headers: foreign_admin.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403, 404])
    end
  end

  describe 'GET /api/v1/accounts/:id/tasks/reports' do
    before { create_list(:task, 2, account: account, created_by_user: admin) }

    it 'returns aggregated metrics' do
      get "/api/v1/accounts/#{account.id}/tasks/reports",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'created_vs_completed', 'avg_time_to_complete_by_agent',
        'overdue_rate_by_agent', 'open_urgency_distribution'
      )
    end

    it 'forbids non-admins' do
      get "/api/v1/accounts/#{account.id}/tasks/reports",
          headers: agent.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403])
    end
  end

  describe 'POST /api/v1/accounts/:id/tasks/:id/convert_to_kanban_card' do
    let(:task) { create(:task, account: account, created_by_user: admin) }
    let(:funnel) { create(:funnel, account: account) }
    let(:stage)  { create(:funnel_stage, funnel: funnel) }

    it 'creates a kanban_task and cross-links the source task' do
      expect do
        post "/api/v1/accounts/#{account.id}/tasks/#{task.id}/convert_to_kanban_card",
             params: { funnel_id: funnel.id, funnel_stage_id: stage.id },
             headers: admin.create_new_auth_token, as: :json
      end.to change(KanbanTask, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(task.reload.custom_attributes['kanban_card_id']).to eq(KanbanTask.last.id)
    end
  end
end
