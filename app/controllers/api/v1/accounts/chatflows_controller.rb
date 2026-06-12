class Api::V1::Accounts::ChatflowsController < Api::V1::Accounts::BaseController
  before_action :fetch_chatflow, except: [:index, :create]
  before_action :authorize_action

  def index
    @chatflows = policy_scope(Current.account.chatflows).order(created_at: :desc)
  end

  def show
    @nodes = @chatflow.nodes.order(:id)
    @edges = @chatflow.edges.order(:id)
  end

  def create
    @chatflow = Current.account.chatflows.new(permitted_params)
    @chatflow.save!
    @nodes = []
    @edges = []
    render :show
  end

  def update
    @chatflow.update!(permitted_params)
    @nodes = @chatflow.nodes.order(:id)
    @edges = @chatflow.edges.order(:id)
    render :show
  end

  def destroy
    @chatflow.destroy!
    head :ok
  end

  # Flip a draft/archived flow live. Refuses without an entry node so the
  # engine always has somewhere to start.
  def activate
    return render_missing_start_node if @chatflow.start_node_id.blank?

    @chatflow.status_active!
    render_summary
  end

  def archive
    @chatflow.status_archived!
    # Stop any in-flight runs so an archived flow never keeps replying.
    # Bulk flip is intentional — no per-row callbacks needed here.
    # rubocop:disable Rails/SkipsModelValidations
    @chatflow.executions.live.update_all(status: ChatflowExecution.statuses[:aborted], updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
    render_summary
  end

  # Test mode: the flow runs only for the given tester number, even while it
  # is still a draft, so operators can rehearse before publishing.
  def test
    @chatflow.update!(test_mode: true, test_phone: params[:phone].to_s.strip)
    render_summary
  end

  def stop_test
    @chatflow.update!(test_mode: false)
    render_summary
  end

  # Externally-triggered start (webhook trigger). Integrators POST a
  # conversation_id and the engine runs this flow on that conversation.
  def run
    conversation = Current.account.conversations.find_by(display_id: params[:conversation_id])
    return render json: { error: 'conversation_not_found' }, status: :not_found if conversation.nil?

    Chatflow::EngineService.force_start(@chatflow, conversation)
    head :ok
  end

  private

  def fetch_chatflow
    @chatflow = Current.account.chatflows.find(params[:id])
  end

  def authorize_action
    case action_name
    when 'index', 'create'
      authorize(Chatflow)
    else
      authorize(@chatflow)
    end
  end

  def permitted_params
    params.require(:chatflow).permit(
      :name, :description, :inbox_id, :start_node_id, :trigger_type, :color,
      trigger_config: { keywords: [] }
    )
  end

  def render_summary
    render partial: 'chatflow', locals: { chatflow: @chatflow }
  end

  def render_missing_start_node
    render json: {
      error: 'missing_start_node',
      message: I18n.t('errors.chatflow.missing_start_node',
                      default: 'Defina a etapa inicial do fluxo antes de ativá-lo.')
    }, status: :unprocessable_entity
  end
end
