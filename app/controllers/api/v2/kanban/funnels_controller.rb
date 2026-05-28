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

  # Pagination helpers shared across the v2 controllers. Defaults to
  # page 1 / 25 per page. Capped at 100 to stop accidental DOS via a
  # naive integration that asks for `per_page=10000`.
  def paginate(scope)
    page = (params[:page] || 1).to_i.clamp(1, 100_000)
    per = (params[:per_page] || 25).to_i.clamp(1, 100)
    @_total_count = scope.count
    @_total_pages = (@_total_count.to_f / per).ceil
    @_page = page
    @_per = per
    scope.offset((page - 1) * per).limit(per)
  end

  def meta_for(_scope)
    {
      page: @_page,
      per_page: @_per,
      total: @_total_count,
      total_pages: @_total_pages
    }
  end
end
