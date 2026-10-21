class Api::V1::Accounts::ChatflowsController < Api::V1::Accounts::BaseController
  before_action :fetch_chatflow, except: [:index, :create, :templates, :from_template, :options]
  before_action :authorize_action

  def index
    @chatflows = policy_scope(Current.account.chatflows).order(created_at: :desc)
    @stats = execution_stats
  end

  # Biblioteca de modelos prontos do vertical da conta.
  def templates
    render json: { templates: Chatflow::TemplateLibrary.available(Current.account).map(&:summary) }
  end

  # Instala um modelo: fluxo em RASCUNHO, para o dono revisar antes de ligar.
  def from_template
    template = Chatflow::TemplateLibrary.find(params[:key])
    return render json: { error: 'template_not_found' }, status: :not_found if template.nil?

    @chatflow = Chatflow::TemplateLibrary.new(account: Current.account, template: template).install!
    @nodes = @chatflow.nodes.order(:id)
    @edges = @chatflow.edges.order(:id)
    render :show
  end

  # O que os editores dos blocos novos precisam escolher: listas de
  # distribuição (quando o recurso existe), outros fluxos e disparos.
  def options
    render json: {
      lists_available: Chatflow::ListBridge.available?,
      lists: Chatflow::ListBridge.lists_for(Current.account),
      chatflows: Current.account.chatflows.where.not(status: :archived).order(:name).map { |f| f.slice(:id, :name, :status) },
      broadcasts: Current.account.broadcasts.order(created_at: :desc).limit(50).map { |b| b.slice(:id, :name, :status) }
    }
  end

  def funnel
    days = params[:days].to_i.clamp(1, 365)
    days = 30 if params[:days].blank?
    render json: Chatflow::FunnelReport.new(@chatflow, since: days.days.ago).perform
  end

  # Roda o fluxo numa conversa de mentira dentro de uma transação desfeita:
  # nada é gravado e nada sai para o WhatsApp.
  def simulate
    result = Chatflow::Simulator.new(
      @chatflow, inputs: params[:inputs], seed: params[:seed],
                 contact: params.fetch(:contact, {}).permit(:name, custom_attributes: {}).to_h
    ).perform
    render json: result
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
    when 'index', 'create', 'templates', 'from_template', 'options'
      authorize(Chatflow)
    else
      authorize(@chatflow)
    end
  end

  def permitted_params
    params.require(:chatflow).permit(
      :name, :description, :inbox_id, :start_node_id, :trigger_type, :color,
      # Cada chave do trigger_config citada uma a uma, de propósito: um permit
      # que só listava `keywords` descartava o resto em SILÊNCIO. A regra de
      # reinício existia na tela e o motor sabia lê-la — ela só nunca chegava ao
      # banco. Configuração que não faz nada é pior que configuração que não existe.
      trigger_config: [:sender_name, :position_x, :position_y, :no_reply_minutes, :pause_on_agent_reply,
                       { keywords: [], restart: [:mode, :hours], label_ids: [], broadcast_ids: [], list_ids: [],
                         date: [:kind, :attribute_key, :days, :label_id, :hour] }]
    )
  end

  def execution_stats
    counts = ChatflowExecution.where(account_id: Current.account.id, created_at: 30.days.ago..)
                              .group(:chatflow_id, :status).count
    counts.each_with_object(Hash.new { |h, k| h[k] = { 'started' => 0, 'completed' => 0, 'live' => 0 } }) do |((id, status), n), acc|
      acc[id]['started'] += n
      acc[id]['completed'] += n if status == 'completed'
      acc[id]['live'] += n if %w[active waiting_input paused].include?(status)
    end
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
