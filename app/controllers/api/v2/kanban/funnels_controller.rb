class Api::V2::Kanban::FunnelsController < Api::V2::Kanban::BaseController
  self.required_scope = { read: 'read:funnels', write: 'write:funnels' }

  before_action :fetch_funnel, only: [:show, :update, :destroy]

  def index
    funnels = current_account.funnels.ordered
    funnels = paginate(funnels)
    render json: { data: funnels.map(&:push_event_data), meta: meta_for(funnels) }
  end

  def show
    render json: { data: @funnel.push_event_data }
  end

  def create
    funnel = current_account.funnels.create!(funnel_params)
    render json: { data: funnel.push_event_data }, status: :created
  end

  def update
    @funnel.update!(funnel_params)
    render json: { data: @funnel.push_event_data }
  end

  def destroy
    @funnel.destroy!
    head :no_content
  rescue ActiveRecord::DeleteRestrictionError => e
    render json: { error: 'funnel_has_dependents', message: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_funnel
    @funnel = current_account.funnels.find(params[:id])
  end

  def funnel_params
    params.require(:funnel).permit(:name, :description, :position, automation_settings: {})
  end
end
