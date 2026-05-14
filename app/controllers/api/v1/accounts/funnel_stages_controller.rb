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
  end

  def reorder
    ids = Array(params[:stage_ids]).map(&:to_i)
    return head :unprocessable_entity if ids.empty?

    FunnelStage.transaction do
      @funnel.funnel_stages.where(id: ids).each do |stage|
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
    params.require(:funnel_stage).permit(:name, :description, :color, :position, :status_type)
  end

  def check_admin_for_reorder
    return if Current.account_user&.administrator?

    raise Pundit::NotAuthorizedError
  end
end
