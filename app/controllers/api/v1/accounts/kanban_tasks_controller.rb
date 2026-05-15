class Api::V1::Accounts::KanbanTasksController < Api::V1::Accounts::BaseController
  before_action :fetch_funnel, only: [:index, :create]
  before_action :fetch_task, except: [:index, :create]
  before_action :check_authorization

  def index
    @tasks = policy_scope(Current.account.kanban_tasks)
             .where(funnel_id: @funnel.id)
             .ordered_in_stage
             .includes(:assignees, :task_labels, :contacts, :conversations, :funnel_stage)
  end

  def show; end

  def create
    stage = @funnel.funnel_stages.find(permitted_params.fetch(:funnel_stage_id))
    @task = Current.account.kanban_tasks.new(permitted_params.merge(funnel: @funnel, funnel_stage: stage))
    assignees_changed = apply_associations(@task)
    @task.save!
    Kanban::AutomationService.handle_task_assignees_changed(@task) if assignees_changed
  end

  def update
    if params[:kanban_task].key?(:funnel_stage_id)
      stage = @task.funnel.funnel_stages.find(params[:kanban_task][:funnel_stage_id])
      @task.funnel_stage = stage
    end
    @task.assign_attributes(permitted_params.except(:funnel_stage_id))
    assignees_changed = apply_associations(@task)
    @task.save!
    Kanban::AutomationService.handle_task_assignees_changed(@task) if assignees_changed
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
    authorize(@funnel, :show?)
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
      :start_date, :due_date, :funnel_stage_id
    )
  end

  def apply_associations(task)
    assignees_changed = apply_ids(task, param: :assignee_ids, setter: :assignee_ids, source: Current.account.users)
    apply_ids(task, param: :label_ids, setter: :task_label_ids, source: Current.account.labels)
    apply_ids(task, param: :conversation_ids, setter: :conversation_ids, source: Current.account.conversations)
    apply_ids(task, param: :contact_ids, setter: :contact_ids, source: Current.account.contacts)
    assignees_changed
  end

  def apply_ids(task, param:, setter:, source:)
    return false unless params[:kanban_task].key?(param)

    ids = Array(params[:kanban_task][param]).map(&:to_i)
    filtered = source.where(id: ids).pluck(:id)
    task.public_send("#{setter}=", filtered)
    true
  end
end
