class Api::V1::Accounts::FunnelsController < Api::V1::Accounts::BaseController
  before_action :fetch_funnel, except: [:index, :create]
  before_action :check_authorization

  def index
    @funnels = policy_scope(Current.account.funnels).ordered.includes(:funnel_stages)
  end

  def show; end

  def create
    @funnel = Current.account.funnels.new(permitted_params)
    apply_associations(@funnel)
    @funnel.save!
  end

  def update
    @funnel.assign_attributes(permitted_params)
    apply_associations(@funnel)
    @funnel.save!
  end

  def destroy
    @funnel.destroy!
    head :ok
  end

  private

  def fetch_funnel
    @funnel = Current.account.funnels.find(params[:id])
  end

  def permitted_params
    params.require(:funnel).permit(:name, :description, :position, automation_settings: Funnel::AUTOMATION_KEYS)
  end

  def apply_associations(funnel)
    if params[:funnel].key?(:inbox_ids)
      ids = Array(params[:funnel][:inbox_ids]).map(&:to_i)
      funnel.inbox_ids = Current.account.inboxes.where(id: ids).ids
    end
    return unless params[:funnel].key?(:agent_ids)

    ids = Array(params[:funnel][:agent_ids]).map(&:to_i)
    funnel.agent_ids = Current.account.users.where(id: ids).ids
  end
end
