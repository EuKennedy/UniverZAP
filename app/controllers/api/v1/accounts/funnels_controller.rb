class Api::V1::Accounts::FunnelsController < Api::V1::Accounts::BaseController
  before_action :fetch_funnel, except: [:index, :create]
  before_action :authorize_action

  # Api::BaseController#check_authorization hands the class to Pundit
  # (`authorize(Funnel)`). FunnelPolicy#member_access? calls
  # `record.funnel_agents`, which blows up with NoMethodError on the class
  # and turns every show / update / destroy into a 500. Use the fetched
  # instance for member actions; index/create still authorize against the
  # class since policy_scope is enough for the list and admin-only create.
  def authorize_action
    case action_name
    when 'index', 'create'
      authorize(Funnel)
    else
      authorize(@funnel)
    end
  end

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
  rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::RecordNotDestroyed => e
    # Rails 7 raises `RecordNotDestroyed` (not `DeleteRestrictionError`)
    # when a `restrict_with_error` association blocks deletion. The model
    # also prepends `purge_kanban_tasks` so the cascade order is no
    # longer the failure mode here; this rescue is the belt-and-braces
    # so any future child with `restrict_with_error` (e.g. inbox
    # attachments) still surfaces as a friendly 422 instead of a 500.
    Rails.logger.warn("[Funnel#destroy] blocked id=#{@funnel&.id}: #{e.message}")
    render json: {
      error: 'funnel_has_dependents',
      message: I18n.t('errors.funnel.destroy_blocked',
                      default: 'Mova ou exclua as tarefas e dependências do funil antes de removê-lo.')
    }, status: :unprocessable_entity
  end

  private

  def fetch_funnel
    @funnel = Current.account.funnels.find(params[:id])
  end

  def permitted_params
    params.require(:funnel).permit(:name, :description, :position, automation_settings: Funnel::AUTOMATION_KEYS)
  end

  def apply_associations(funnel)
    apply_inbox_ids(funnel)
    apply_agent_ids(funnel)
  end

  def apply_inbox_ids(funnel)
    return unless params[:funnel].key?(:inbox_ids)

    ids = Array(params[:funnel][:inbox_ids]).map(&:to_i)
    funnel.inbox_ids = Current.account.inboxes.where(id: ids).ids
  end

  def apply_agent_ids(funnel)
    return unless params[:funnel].key?(:agent_ids)

    ids = Array(params[:funnel][:agent_ids]).map(&:to_i)
    funnel.agent_ids = Current.account.users.where(id: ids).ids
  end
end
