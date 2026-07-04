require 'rails_helper'

RSpec.describe Api::V1::Accounts::KanbanTasksController, type: :request do
  let(:account) { create(:account) }
  let(:admin)   { create(:user, account: account, role: :administrator) }
  let(:funnel)  { create(:funnel, account: account) }
  let(:stage)   { create(:funnel_stage, funnel: funnel) }

  describe 'POST /api/v1/accounts/:account_id/funnels/:funnel_id/kanban_tasks' do
    let(:due_at)   { 3.days.from_now.change(usec: 0) }
    let(:start_at) { Time.current.change(usec: 0) }

    def create_task(kanban_task_params)
      post "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/kanban_tasks",
           params: { kanban_task: kanban_task_params },
           headers: admin.create_new_auth_token,
           as: :json
    end

    it 'persists a task without dates' do
      expect do
        create_task(title: 'No deadline', funnel_stage_id: stage.id)
      end.to change(funnel.kanban_tasks, :count).by(1)

      expect(response).to have_http_status(:success)
    end

    # Regressão: o front manda start_date/due_date como epoch em segundos.
    # Antes da correção o Integer cru ia direto pra coluna :datetime e o
    # save! estourava — a tarefa não salvava. Este teste tranca esse fluxo.
    it 'persists a task when start_date/due_date arrive as epoch seconds' do
      expect do
        create_task(
          title: 'With deadline',
          funnel_stage_id: stage.id,
          start_date: start_at.to_i,
          due_date: due_at.to_i
        )
      end.to change(funnel.kanban_tasks, :count).by(1)

      expect(response).to have_http_status(:success)

      task = funnel.kanban_tasks.order(:id).last
      expect(task.start_date.to_i).to eq(start_at.to_i)
      expect(task.due_date.to_i).to eq(due_at.to_i)
    end

    it 'assigns agents passed as assignee_ids together with a due_date' do
      agent = create(:user, account: account, role: :agent)

      create_task(
        title: 'Assigned',
        funnel_stage_id: stage.id,
        assignee_ids: [agent.id],
        due_date: due_at.to_i
      )

      expect(response).to have_http_status(:success)
      expect(funnel.kanban_tasks.last.assignee_ids).to contain_exactly(agent.id)
    end
  end
end
