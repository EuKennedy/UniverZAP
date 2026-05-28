# Dashboard-side Tasks API. Authentication piggybacks on the standard
# Chatwoot session (devise_token_auth) inherited from BaseController;
# token / scope enforcement lives in the v2 namespace instead. All
# fetches funnel through `Current.account.tasks` so cross-tenant URLs
# yield 404 instead of leaking shape.
#
# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::TasksController < Api::V1::Accounts::BaseController
  before_action :fetch_task, except: [:index, :create]
  before_action :authorize_action

  def index
    tasks = Tasks::Finder.new(account: Current.account, user: Current.user, params: params).call
    render json: tasks.map(&:push_event_data)
  end

  def show
    render json: @task.push_event_data
  end

  def create
    @task = Current.account.tasks.create!(create_params.merge(created_by_user: Current.user))
    render json: @task.push_event_data, status: :created
  end

  def update
    @task.update!(update_params)
    render json: @task.push_event_data
  end

  def destroy
    @task.destroy!
    head :ok
  end

  def assign
    user = fetch_account_user(params.require(:user_id))
    @task.task_assignees.create!(user: user)
    render json: @task.reload.push_event_data
  end

  def unassign
    assignment = @task.task_assignees.find_by!(user_id: params[:user_id])
    assignment.destroy!
    render json: @task.reload.push_event_data
  end

  def complete
    @task.update!(status: :done, completed_at: Time.current)
    render json: @task.push_event_data
  end

  def add_comment
    comment = @task.task_comments.create!(user: Current.user, body: comment_body)
    render json: comment.push_event_data, status: :created
  end

  def activities
    page = (params[:page] || 1).to_i.clamp(1, 100_000)
    per = (params[:per_page] || 25).to_i.clamp(1, 100)
    scope = @task.task_activities.recent_first
    activities = scope.offset((page - 1) * per).limit(per)
    render json: {
      data: activities.map(&:push_event_data),
      meta: { page: page, per_page: per, total: scope.count }
    }
  end

  private

  def fetch_task
    @task = Current.account.tasks.find(params[:id])
  end

  # `authorize_action` mirrors the kanban_tasks pattern: the class
  # itself is authorized for index/create (so the policy can rely on a
  # Task instance everywhere else), and member actions pass the record.
  def authorize_action
    record = action_uses_class? ? Task : @task
    authorize(record, "#{action_name}?", policy_class: TaskPolicy)
  end

  def action_uses_class?
    %w[index create].include?(action_name)
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

  def comment_body
    raw = params[:body]
    return {} if raw.blank?

    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
  end

  def fetch_account_user(user_id)
    membership = Current.account.account_users.find_by!(user_id: user_id)
    membership.user
  end
end
# rubocop:enable Metrics/ClassLength
