class Api::V1::Accounts::KanbanAutomationsController < Api::V1::Accounts::BaseController
  before_action :fetch_automation, except: [:index, :create]
  before_action :check_authorization

  def index
    automations = Current.account.kanban_automations
    automations = automations.where(funnel_id: params[:funnel_id]) if params[:funnel_id].present?
    automations = automations.where(event_name: params[:event_name]) if params[:event_name].present?
    automations = automations.where(active: ActiveModel::Type::Boolean.new.cast(params[:active])) if params.key?(:active)

    render json: automations.order(created_at: :desc).map(&:push_event_data)
  end

  def show
    render json: @automation.push_event_data
  end

  def create
    @automation = Current.account.kanban_automations.create!(permitted_params)
    render json: @automation.push_event_data, status: :created
  end

  def update
    @automation.update!(permitted_params)
    render json: @automation.push_event_data
  end

  def destroy
    @automation.destroy!
    head :ok
  end

  # POST /kanban_automations/:id/test
  # Dry-run the rule against a single task to preview the action chain
  # without committing any side effects to other systems. Returns the
  # condition match result + a list of action plans. Useful for the
  # dashboard's "Test rule" button.
  def test
    task = Current.account.kanban_tasks.find(params.require(:task_id))
    matched = Kanban::Automations::ConditionMatcher.matches?(rule: @automation, task: task)

    render json: {
      matched: matched,
      task_id: task.id,
      conditions_evaluated: @automation.conditions,
      planned_actions: @automation.actions_array.map { |a| { type: a[:type], params: a[:params] } }
    }
  end

  # POST /kanban_automations/:id/run
  # Force-execute the rule against a single task NOW (synchronously).
  # Bypasses event matching — useful for backfills + manual triggers.
  def run
    task = Current.account.kanban_tasks.find(params.require(:task_id))
    result = Kanban::Automations::Executor.call(rule: @automation, task: task)
    render json: { status: result, automation: @automation.reload.push_event_data }
  end

  private

  def fetch_automation
    @automation = Current.account.kanban_automations.find(params[:id])
  end

  # Strong params can't express the open shape of `conditions` (any keys)
  # nor the open shape of action `params` (varies per action type). We
  # permit the scalar attributes via strong params + lift the JSONB
  # blobs from the raw payload, then the model validator enforces
  # structure server-side.
  def permitted_params
    scalars = params.require(:kanban_automation)
                    .permit(:name, :description, :event_name, :funnel_id, :active)
                    .to_h
    scalars.merge(
      'conditions' => permitted_conditions,
      'actions' => permitted_actions
    )
  end

  def permitted_conditions
    raw = params[:kanban_automation][:conditions]
    return {} if raw.blank?
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw.is_a?(Hash) ? raw : {}
  end

  def permitted_actions
    raw = params[:kanban_automation][:actions]
    return [] if raw.blank?

    Array(raw).map { |action| normalize_action(action) }
  end

  def normalize_action(action)
    return {} unless action.respond_to?(:to_unsafe_h)

    raw = action.to_unsafe_h
    { 'type' => raw['type'].to_s, 'params' => raw['params'].is_a?(Hash) ? raw['params'] : {} }
  end
end
