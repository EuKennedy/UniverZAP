# Formulários nativos do WhatsApp (Flows) de uma caixa Cloud API, criados a
# partir dos modelos do vertical ou de um Flow JSON colado, e publicados na
# Meta daqui mesmo.
#
# Leitura liberada para a conta (o builder do Chatflow precisa listar);
# escrita só para administrador, porque publicar compromete o número.
class Api::V1::Accounts::WhatsappFlowsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin, except: [:index, :show, :templates]
  before_action :set_flow, only: [:show, :update, :destroy, :publish, :deprecate, :sync]

  def index
    @flows = Current.account.whatsapp_flows.order(created_at: :desc)
    @flows = @flows.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
  end

  def show; end

  def templates
    render json: { templates: Whatsapp::Flows::TemplateLibrary.available(Current.account).map { |t| template_summary(t) } }
  end

  def create
    inbox = Current.account.inboxes.find(flow_params[:inbox_id])
    return render_cloud_required unless cloud_channel?(inbox)

    @flow = Current.account.whatsapp_flows.new(build_attributes(inbox))
    @flow.save!
    push_and_render(inbox)
  end

  def update
    @flow.update!(flow_params.slice(:name, :category, :flow_json))
    push_and_render(@flow.inbox)
  end

  def destroy
    render_result(service_for(@flow).destroy(@flow))
  end

  def publish
    render_result(service_for(@flow).publish(@flow))
  end

  def deprecate
    render_result(service_for(@flow).deprecate(@flow))
  end

  def sync
    render_result(service_for(@flow).sync(@flow))
  end

  private

  def set_flow
    @flow = Current.account.whatsapp_flows.find(params[:id])
  end

  def flow_params
    params.require(:whatsapp_flow).permit(:inbox_id, :template_key, :name, :category).tap do |permitted|
      # Flow JSON é um documento livre; o modelo valida a forma mínima.
      permitted[:flow_json] = raw_flow_json if params[:whatsapp_flow].key?(:flow_json)
    end
  end

  def raw_flow_json
    raw = params[:whatsapp_flow][:flow_json]
    raw = JSON.parse(raw) if raw.is_a?(String)
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
  rescue JSON::ParserError
    {}
  end

  # Modelo do vertical ou JSON colado. O modelo garante os atributos que o
  # mapeamento vai preencher; o JSON colado não mapeia nada até alguém dizer.
  def build_attributes(inbox)
    attrs = { inbox: inbox, name: flow_params[:name], category: flow_params[:category].presence || 'OTHER',
              flow_json: flow_params[:flow_json] }
    template = Whatsapp::Flows::TemplateLibrary.find(flow_params[:template_key]) if flow_params[:template_key].present?
    return attrs if template.blank?

    attrs.merge(
      name: flow_params[:name].presence || template.name,
      category: template.category,
      template_key: template.key,
      field_mappings: template.field_mappings,
      flow_json: Whatsapp::Flows::TemplateLibrary.new(account: Current.account, template: template).build
    )
  end

  # Salvo aqui, enviado à Meta em seguida. Se a Meta recusar, o Flow fica como
  # rascunho local com o motivo: o operador corrige e reenvia, em vez de
  # perder o que escreveu.
  def push_and_render(inbox)
    result = Whatsapp::Flows::ManagementService.new(inbox.channel).push(@flow)
    return render :show if result.success?

    render json: { error: result.error, whatsapp_flow: { id: @flow.id } }, status: :unprocessable_entity
  end

  def render_result(result)
    return render json: { error: result.error }, status: :unprocessable_entity unless result.success?
    return head :ok if action_name == 'destroy'

    @flow = result.flow
    render :show
  end

  def service_for(flow)
    Whatsapp::Flows::ManagementService.new(flow.inbox.channel)
  end

  def cloud_channel?(inbox)
    inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'whatsapp_cloud'
  end

  def render_cloud_required
    render json: { error: 'cloud_provider_required' }, status: :unprocessable_entity
  end

  def template_summary(template)
    { key: template.key, name: template.name, description: template.description, category: template.category }
  end

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end
end
