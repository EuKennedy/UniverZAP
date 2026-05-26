class Api::V1::Accounts::KanbanTaskActivitiesController < Api::V1::Accounts::BaseController
  before_action :fetch_task
  before_action :check_authorization

  def index
    @activities = @task.activities.recent(100).includes(:user)
  end

  private

  def fetch_task
    @task = Current.account.kanban_tasks.find(params[:kanban_task_id])
  end
end
