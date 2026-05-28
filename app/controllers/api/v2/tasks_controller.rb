# Public Tasks API v2 — Bearer-authenticated, account-scoped via the
# token. Mirrors the kanban v2 surface so n8n/Zapier/Make integrations
# follow one mental model.
class Api::V2::TasksController < Api::V2::Tasks::BaseController
  self.required_scope = { read: 'read:user_tasks', write: 'write:user_tasks' }

  before_action :fetch_task, only: [:show, :update, :destroy, :assign, :complete]

  def index
    tasks = paginate(filtered_scope)
    render json: { data: tasks.map(&:push_event_data), meta: meta_for(tasks) }
  end

  def show
    render json: { data: @task.push_event_data }
  end

  def create
    task = current_account.tasks.create!(create_params.merge(created_by_user: token_user))
    render json: { data: task.push_event_data }, status: :created
  end

  def update
    @task.update!(update_params)
    render json: { data: @task.push_event_data }
  end

  def destroy
    @task.destroy!
    head :no_content
  end

  def assign
    user = current_account.users.find(params.require(:user_id))
    @task.task_assignees.create!(user: user)
    render json: { data: @task.reload.push_event_data }
  end

  def complete
    @task.update!(status: :done, completed_at: Time.current)
    render json: { data: @task.push_event_data }
  end

  private

  def fetch_task
    @task = current_account.tasks.find(params[:id])
  end

  def filtered_scope
    scope = current_account.tasks
    scope = scope.where(status: status_value) if status_value
    scope = scope.where(urgency: urgency_value) if urgency_value
    scope = scope.assigned_to(params[:assignee_id]) if params[:assignee_id].present?
    scope = scope.where('title ILIKE ?', "%#{params[:q]}%") if params[:q].present?
    scope.order(updated_at: :desc)
  end

  def status_value
    return nil unless Task.statuses.key?(params[:status].to_s)

    Task.statuses[params[:status]]
  end

  def urgency_value
    return nil unless Task.urgencies.key?(params[:urgency].to_s)

    Task.urgencies[params[:urgency]]
  end

  # The public token doesn't carry a user identity — fall back to the
  # token's creator so `created_by_user_id` is never NULL on tasks
  # made through the public API. Accounts can lock this down further by
  # requiring `created_by_user_id` in the payload if they care.
  def token_user
    explicit = params.dig(:task, :created_by_user_id)
    return current_account.users.find(explicit) if explicit.present?

    current_token.created_by_user || current_account.users.first
  end

  def create_params
    params.require(:task).permit(:title, :urgency, :status, :due_date, :notify_assignees,
                                 description: {}, custom_attributes: {})
  end

  def update_params
    params.require(:task).permit(:title, :urgency, :status, :due_date, :completed_at,
                                 :notify_assignees, :position,
                                 description: {}, custom_attributes: {})
  end
end
