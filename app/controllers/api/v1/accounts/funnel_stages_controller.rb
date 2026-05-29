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
  rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::RecordNotDestroyed => e
    # Two scenarios reach this rescue:
    #   1. The stage still has `kanban_tasks` (`restrict_with_error` →
    #      Rails 7 raises `RecordNotDestroyed`, NOT
    #      `DeleteRestrictionError`).
    #   2. The stage is the funnel's last column and the
    #      `ensure_not_last_stage` callback aborts to keep the board
    #      coherent.
    # Both deserve a 422 with a clear, operator-friendly hint instead of
    # an opaque server error in the toast.
    message = if @stage.errors[:base].any?
                @stage.errors[:base].first
              else
                I18n.t('errors.funnel_stage.has_tasks',
                       default: 'Mova as tarefas desta etapa antes de removê-la.')
              end
    Rails.logger.warn("[FunnelStage#destroy] blocked id=#{@stage&.id}: #{e.message}")
    render json: { error: 'stage_destroy_blocked', message: message }, status: :unprocessable_entity
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
