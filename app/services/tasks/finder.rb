# Task list-scope resolver — composes scope, status, urgency, assignee
# and search filters into one chain so the controller can stay thin.
# Lives in a service object (not a controller helper) because the
# scope logic is shared between v1 (dashboard) and v2 (token API).
class Tasks::Finder
  ALLOWED_SCOPES = %w[mine created_by_me team all].freeze
  ALLOWED_STATUS = %w[open in_progress blocked done cancelled].freeze
  ALLOWED_URGENCY = %w[none low medium high urgent].freeze

  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params
  end

  # `push_event_data` on each row walks `assignees`, `task_comments` and
  # `task_activities` to build the association summary the dashboard
  # renders inline. Without these eager loads the list endpoint fires
  # O(rows × 3) extra queries on every render — painful on the "Time" /
  # "Todas" tabs where an account easily holds hundreds of tasks.
  TASK_LIST_INCLUDES = [:assignees, :task_comments, :task_activities, :created_by_user].freeze

  def call
    chain = apply_visibility(@account.tasks)
    chain = apply_filters(chain)
    chain.includes(TASK_LIST_INCLUDES).order(updated_at: :desc)
  end

  private

  def apply_visibility(scope)
    case @params[:scope].to_s
    when 'mine'          then scope.assigned_to(@user.id)
    when 'created_by_me' then scope.created_by(@user.id)
    else scope
    end
  end

  def apply_filters(scope)
    scope = scope.where(status: status_value) if status_value
    scope = scope.where(urgency: urgency_value) if urgency_value
    scope = scope.assigned_to(@params[:assignee_id]) if @params[:assignee_id].present?
    scope = scope.where('due_date <= ?', due_before_value) if due_before_value
    scope = scope.where('title ILIKE ?', "%#{@params[:q]}%") if @params[:q].present?
    scope
  end

  def status_value
    return nil unless ALLOWED_STATUS.include?(@params[:status].to_s)

    Task.statuses[@params[:status]]
  end

  def urgency_value
    return nil unless ALLOWED_URGENCY.include?(@params[:urgency].to_s)

    Task.urgencies[@params[:urgency]]
  end

  def due_before_value
    return nil if @params[:due_before].blank?

    Time.zone.parse(@params[:due_before])
  rescue ArgumentError
    nil
  end
end
