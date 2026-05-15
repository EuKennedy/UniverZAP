class Api::V1::Accounts::Conversations::KanbanTasksController < Api::V1::Accounts::Conversations::BaseController
  def index
    @tasks = policy_scope(@conversation.kanban_tasks)
             .ordered_in_stage
             .includes(:assignees, :task_labels, :contacts, :conversations, :funnel_stage)
    render 'api/v1/accounts/kanban_tasks/index'
  end
end
