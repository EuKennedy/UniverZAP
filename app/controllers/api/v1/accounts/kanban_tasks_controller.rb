class Api::V1::Accounts::KanbanTasksController < Api::V1::Accounts::BaseController
  before_action :fetch_funnel, only: [:index, :create, :export]
  before_action :fetch_task, except: [:index, :create, :export]
  before_action :authorize_action

  # Pundit's default `check_authorization` constantises the controller name
  # ("KanbanTask"). The KanbanTaskPolicy needs the funnel for list/create
  # actions (no record yet) and the task itself for member actions; passing
  # the class makes `record.funnel` blow up with NoMethodError on the class.
  def authorize_action
    case action_name
    when 'index', 'create', 'export'
      authorize(@funnel, :show?, policy_class: FunnelPolicy)
    else
      authorize(@task)
    end
  end

  def index
    @tasks = policy_scope(Current.account.kanban_tasks)
             .where(funnel_id: @funnel.id)
             .root_tasks
             .ordered_in_stage
             .includes(:assignees, :task_labels, :contacts, :conversations, :funnel_stage, :subtasks)
  end

  def show; end

  # CSV export — devolve as tasks-raiz do funil em formato planilha pra
  # análise offline. Mantém a mesma ordenação do board.
  def export
    tasks = policy_scope(Current.account.kanban_tasks)
            .where(funnel_id: @funnel.id)
            .root_tasks
            .ordered_in_stage
            .includes(:funnel_stage, :assignees, :task_labels, :contacts, :conversations)
    send_data Kanban::CsvExportService.new(tasks, @funnel).call,
              type: 'text/csv',
              disposition: 'attachment',
              filename: "univerzap-funnel-#{@funnel.id}-#{Time.current.to_i}.csv"
  end

  def create
    stage = @funnel.funnel_stages.find(permitted_params.fetch(:funnel_stage_id))
    @task = Current.account.kanban_tasks.new(permitted_params.merge(funnel: @funnel, funnel_stage: stage))
    assignees_changed = apply_associations(@task)
    @task.save!
    Kanban::AutomationService.handle_task_assignees_changed(@task) if assignees_changed
    Kanban::ActivityLogger.log_created(@task, Current.user)
  end

  def update
    if params[:kanban_task].key?(:funnel_stage_id)
      stage = @task.funnel.funnel_stages.find(params[:kanban_task][:funnel_stage_id])
      @task.funnel_stage = stage
    end
    @task.assign_attributes(permitted_params.except(:funnel_stage_id))
    previous_assignee_ids = @task.assignee_ids.dup
    previous_label_ids = @task.task_label_ids.dup
    assignees_changed = apply_associations(@task)
    snapshot = @task.changes
    @task.save!
    Kanban::AutomationService.handle_task_assignees_changed(@task) if assignees_changed
    Kanban::ActivityLogger.log_changes(
      @task,
      Current.user,
      snapshot,
      previous_assignee_ids: previous_assignee_ids,
      previous_label_ids: previous_label_ids
    )
  end

  def destroy
    @task.destroy!
    head :ok
  end

  def move
    stage = @task.funnel.funnel_stages.find(params[:funnel_stage_id])
    new_position = params[:position].to_i
    KanbanTask.transaction do
      @task.update!(funnel_stage: stage, position: new_position.positive? ? new_position : 1)
    end
    render :show
  end

  def attach_conversation
    conversation = find_conversation(params[:conversation_id])
    @task.conversations << conversation unless @task.conversation_ids.include?(conversation.id)
    render :show
  end

  def detach_conversation
    conversation = find_conversation(params[:conversation_id])
    @task.conversations.destroy(conversation)
    render :show
  end

  private

  def fetch_funnel
    @funnel = Current.account.funnels.find(params[:funnel_id])
  end

  def fetch_task
    @task = Current.account.kanban_tasks.find(params[:id])
  end

  def find_conversation(identifier)
    Current.account.conversations.find_by!(display_id: identifier)
  end

  def permitted_params
    params.require(:kanban_task).permit(
      :title, :description, :priority, :position,
      :start_date, :due_date, :funnel_stage_id,
      :parent_task_id, :estimate_minutes, :completed_at
    )
  end

  def apply_associations(task)
    assignees_changed = apply_ids(task, param: :assignee_ids, setter: :assignee_ids, source: Current.account.users)
    apply_ids(task, param: :label_ids, setter: :task_label_ids, source: Current.account.labels)
    apply_ids(task, param: :conversation_ids, setter: :conversation_ids, source: Current.account.conversations)
    apply_ids(task, param: :contact_ids, setter: :contact_ids, source: Current.account.contacts)
    apply_custom_values(task) if params[:kanban_task].key?(:custom_values)
    assignees_changed
  end

  def apply_custom_values(task)
    fields = task.funnel.custom_fields.index_by(&:id)
    Array(params[:kanban_task][:custom_values]).each do |entry|
      field = fields[entry[:funnel_custom_field_id].to_i]
      next if field.blank?

      upsert_custom_value(task, field, entry[:value])
    end
  end

  def upsert_custom_value(task, field, raw_value)
    record = task.custom_values.find_or_initialize_by(funnel_custom_field: field)
    if raw_value.blank?
      record.destroy if record.persisted?
      return
    end
    record.update!(value: serialize_custom_value(raw_value))
  end

  def serialize_custom_value(raw_value)
    raw_value.is_a?(Array) ? raw_value.to_json : raw_value.to_s
  end

  def apply_ids(task, param:, setter:, source:)
    return false unless params[:kanban_task].key?(param)

    ids = Array(params[:kanban_task][param]).map(&:to_i)
    filtered = source.where(id: ids).pluck(:id)
    task.public_send("#{setter}=", filtered)
    true
  end
end
