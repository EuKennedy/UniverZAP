# Dashboard-side Tasks API. Authentication piggybacks on the standard
# Chatwoot session (devise_token_auth) inherited from BaseController;
# token / scope enforcement lives in the v2 namespace instead. All
# fetches funnel through `Current.account.tasks` so cross-tenant URLs
# yield 404 instead of leaking shape.
#
class Api::V1::Accounts::TasksController < Api::V1::Accounts::BaseController
  before_action :fetch_task, except: [:index, :create, :bulk, :team_workload, :reports]
  before_action :authorize_action

  BULK_ACTIONS = %w[complete delete assign set_urgency].freeze

  def index
    tasks = Tasks::Finder.new(account: Current.account, user: Current.user, params: params).call
    render json: tasks.map(&:push_event_data)
  end

  def show
    render json: @task.push_event_data
  end

  def create
    @task = Current.account.tasks.create!(create_params.merge(created_by_user: Current.user))
    apply_recurrence_metadata(@task)
    render json: @task.reload.push_event_data, status: :created
  end

  def update
    @task.update!(update_params)
    apply_recurrence_metadata(@task)
    render json: @task.reload.push_event_data
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

  # Bulk operations over a list of task ids. Runs inside a single
  # transaction per task so a single bad row doesn't poison the rest.
  # Returns `{ ok: <count>, failed: [{ id, reason }] }`.
  def bulk
    ids = Array(params[:task_ids]).map(&:to_i).uniq.compact_blank
    name = bulk_action_name
    return render(json: { error: 'invalid_action' }, status: :unprocessable_entity) unless BULK_ACTIONS.include?(name)

    result = Tasks::BulkAction.new(account: Current.account, user: Current.user, ids: ids,
                                   action: name, payload: bulk_payload).call
    render json: result
  end

  # `params[:action]` collides with the controller's own action name —
  # the user-supplied value is preserved by parsing the raw request body
  # so legacy clients sending `action` keep working alongside the safer
  # `bulk_action` alias.
  def bulk_action_name
    return params[:bulk_action].to_s if params[:bulk_action].present?

    body = parsed_request_body
    (body['bulk_action'] || body['action']).to_s
  end

  def parsed_request_body
    @parsed_request_body ||= begin
      raw = request.raw_post
      raw.present? ? JSON.parse(raw) : {}
    rescue JSON::ParserError
      {}
    end
  end

  # Per-agent workload snapshot, scoped to the current account. Admin-only.
  def team_workload
    render json: Tasks::WorkloadSnapshot.new(account: Current.account).call
  end

  # Aggregated metrics for the Reports tab. Admin-only.
  def reports
    render json: Tasks::ReportsSnapshot.new(account: Current.account, from: report_from, to: report_to).call
  end

  # Materializes the task as a new KanbanTask in the chosen funnel/stage
  # and cross-links both rows via `custom_attributes` so the dashboard
  # can surface the relationship from either side.
  def convert_to_kanban_card
    funnel = Current.account.funnels.find(params.require(:funnel_id))
    stage  = funnel.funnel_stages.find(params.require(:funnel_stage_id))
    card = Tasks::KanbanConverter.new(task: @task, funnel: funnel, stage: stage).call
    render json: { task: @task.reload.push_event_data, kanban_card_id: card.id }, status: :created
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
    %w[index create bulk team_workload reports].include?(action_name)
  end

  def create_params
    params.require(:task).permit(:title, :urgency, :status, :due_date, :notify_assignees,
                                 description: {}, custom_attributes: {}, recurrence_rule: {})
  end

  def update_params
    params.require(:task).permit(:title, :urgency, :status, :due_date, :completed_at,
                                 :notify_assignees, :position,
                                 description: {}, custom_attributes: {}, recurrence_rule: {})
  end

  # Recurrence metadata lives on the task itself but `next_occurrence_at`
  # is a derived value — we recompute it whenever the rule changes so
  # the scheduler/UI never have to.
  def apply_recurrence_metadata(task)
    return unless task.recurring?

    next_at = Tasks::RecurrenceGenerator.next_occurrence(task.recurrence_rule, from: task.due_date || Time.current)
    return if next_at.blank?

    # rubocop:disable Rails/SkipsModelValidations
    task.update_columns(next_occurrence_at: next_at)
    # rubocop:enable Rails/SkipsModelValidations
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

  def bulk_payload
    raw = params[:payload]
    return {} if raw.blank?

    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
  end

  def report_from
    parse_date_param(params[:from]) || 30.days.ago.to_date
  end

  def report_to
    parse_date_param(params[:to]) || Time.current.to_date
  end

  def parse_date_param(raw)
    return nil if raw.blank?

    Time.zone.parse(raw.to_s)&.to_date
  rescue ArgumentError
    nil
  end
end
