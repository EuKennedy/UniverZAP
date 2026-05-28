class Api::V2::Kanban::TasksController < Api::V2::Kanban::BaseController
  self.required_scope = { read: 'read:tasks', write: 'write:tasks' }

  before_action :fetch_task, only: [:show, :update, :destroy, :move]

  def index
    tasks = build_filtered_scope
    tasks = paginate(tasks)
    render json: { data: tasks.map(&:push_event_data), meta: meta_for(tasks) }
  end

  def show
    render json: { data: @task.push_event_data }
  end

  def create
    funnel = current_account.funnels.find(params.require(:funnel_id))
    stage = funnel.funnel_stages.find(params.require(:funnel_stage_id))
    task = funnel.kanban_tasks.create!(task_create_params.merge(account: current_account, funnel_stage: stage))
    render json: { data: task.push_event_data }, status: :created
  end

  def update
    @task.update!(task_update_params)
    render json: { data: @task.push_event_data }
  end

  def destroy
    @task.destroy!
    head :no_content
  end

  # POST /api/v2/kanban/tasks/:id/move
  # Body: { funnel_stage_id: 5 } — same funnel
  #   OR  { funnel_id: 2, funnel_stage_id: 9 } — cross-funnel
  #   OR  { position: 3 } — reorder within current stage
  def move
    if params[:funnel_id].present?
      execute_cross_funnel_move
    elsif params[:funnel_stage_id].present?
      execute_intra_funnel_move
    elsif params[:position].present?
      @task.update!(position: params[:position].to_i)
    else
      render json: { error: 'bad_request', message: 'funnel_id, funnel_stage_id or position required' }, status: :bad_request
      return
    end
    render json: { data: @task.reload.push_event_data }
  end

  private

  def fetch_task
    @task = current_account.kanban_tasks.find(params[:id])
  end

  def build_filtered_scope
    scope = current_account.kanban_tasks
    scope = scope.where(funnel_id: params[:funnel_id]) if params[:funnel_id].present?
    scope = scope.where(funnel_stage_id: params[:funnel_stage_id]) if params[:funnel_stage_id].present?
    scope = scope.where(priority: KanbanTask.priorities[params[:priority]]) if KanbanTask.priorities.key?(params[:priority].to_s)
    scope = scope.where('due_date <= ?', Time.zone.parse(params[:due_before])) if params[:due_before].present?
    scope = scope.where('due_date >= ?', Time.zone.parse(params[:due_after])) if params[:due_after].present?
    scope = scope.joins(:assignees).where(users: { id: params[:assignee_id] }) if params[:assignee_id].present?
    scope = scope.where('title ILIKE ?', "%#{params[:q]}%") if params[:q].present?
    scope.order(updated_at: :desc)
  end

  def execute_cross_funnel_move
    target_funnel = current_account.funnels.find(params[:funnel_id])
    target_stage = target_funnel.funnel_stages.find(params[:funnel_stage_id])
    position = params[:position]&.to_i || (target_stage.kanban_tasks.maximum(:position) || 0) + 1
    @task.update!(funnel: target_funnel, funnel_stage: target_stage, position: position)
  end

  def execute_intra_funnel_move
    stage = @task.funnel.funnel_stages.find(params[:funnel_stage_id])
    position = params[:position]&.to_i || (stage.kanban_tasks.maximum(:position) || 0) + 1
    @task.update!(funnel_stage: stage, position: position)
  end

  def task_create_params
    params.require(:task).permit(:title, :description, :priority, :start_date, :due_date,
                                  :estimate_minutes, :parent_task_id)
  end

  def task_update_params
    params.require(:task).permit(:title, :description, :priority, :start_date, :due_date,
                                  :estimate_minutes, :completed_at)
  end
end
