class Api::V1::Accounts::FunnelStagesController < Api::V1::Accounts::BaseController
  before_action :fetch_funnel
  before_action :fetch_stage, except: [:index, :create, :reorder]
  before_action :check_authorization, except: [:reorder]
  before_action :check_admin_for_reorder, only: [:reorder]

  def index
    @stages = @funnel.funnel_stages.ordered
  end

  def show; end

  def create
    @stage = @funnel.funnel_stages.create!(permitted_params)
  end

  def update
    @stage.update!(permitted_params)
  end

  def destroy
    @stage.destroy!
    head :ok
  rescue ActiveRecord::DeleteRestrictionError
    # Stage has `kanban_tasks dependent: :restrict_with_error`, so any
    # delete with surviving tasks would 500 without this rescue. Return
    # 422 + an operator-friendly hint instead so the UI can offer
    # "mova as tarefas para outra etapa".
    render json: {
      error: 'stage_has_tasks',
      message: 'Mova as tarefas desta etapa antes de removê-la.'
    }, status: :unprocessable_entity
  end

  def reorder
    ids = Array(params[:stage_ids]).map(&:to_i)
    return head :unprocessable_entity if ids.empty?

    FunnelStage.transaction do
      @funnel.funnel_stages.where(id: ids).find_each do |stage|
        stage.update!(position: ids.index(stage.id) + 1)
      end
    end
    @stages = @funnel.funnel_stages.ordered
    render :index
  end

  private

  def fetch_funnel
    @funnel = Current.account.funnels.find(params[:funnel_id])
    authorize(@funnel, :show?)
  end

  def fetch_stage
    @stage = @funnel.funnel_stages.find(params[:id])
  end

  def permitted_params
    params.require(:funnel_stage).permit(:name, :description, :color, :position, :status_type, :wip_limit)
  end

  def check_admin_for_reorder
    return if Current.account_user&.administrator?

    raise Pundit::NotAuthorizedError
  end
end
