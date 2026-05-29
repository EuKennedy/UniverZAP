class Api::V2::Kanban::StagesController < Api::V2::Kanban::BaseController
  self.required_scope = { read: 'read:funnels', write: 'write:funnels' }

  before_action :fetch_funnel_for_stage
  before_action :fetch_stage, only: [:show, :update, :destroy]

  def index
    stages = @funnel.funnel_stages.ordered
    render json: { data: stages.map(&:push_event_data) }
  end

  def show
    render json: { data: @stage.push_event_data }
  end

  def create
    stage = @funnel.funnel_stages.create!(stage_params)
    render json: { data: stage.push_event_data }, status: :created
  end

  def update
    @stage.update!(stage_params)
    render json: { data: @stage.push_event_data }
  end

  def destroy
    @stage.destroy!
    head :no_content
  rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::RecordNotDestroyed => e
    # Symmetrical to v1: `restrict_with_error` raises `RecordNotDestroyed`
    # on Rails 7, and the model now blocks "delete the last stage" via
    # `ensure_not_last_stage`. Surfacing the base error keeps the API
    # client's message in sync with what the operator sees in the UI.
    message = if @stage.errors[:base].any?
                @stage.errors[:base].first
              else
                e.message
              end
    Rails.logger.warn("[Kanban::Stages#destroy] blocked id=#{@stage&.id}: #{e.message}")
    render json: { error: 'stage_destroy_blocked', message: message }, status: :unprocessable_entity
  end

  private

  def fetch_funnel_for_stage
    @funnel = current_account.funnels.find(params[:funnel_id])
  end

  def fetch_stage
    @stage = @funnel.funnel_stages.find(params[:id])
  end

  def stage_params
    params.require(:stage).permit(:name, :description, :color, :position, :status_type, :wip_limit)
  end
end
