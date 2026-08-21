# Templates de mensagem de uma caixa WhatsApp Cloud, criados e acompanhados aqui
# em vez de no Gerenciador da Meta.
#
# Escopado pela conta através de `Current.account.inboxes`: uma caixa de outro
# workspace responde 404 igual a uma que não existe, mesmo com o id certo na URL.
class Api::V1::Accounts::WhatsappTemplatesController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :set_channel

  def index
    render_result(service.list)
  end

  def create
    render_result(service.create(**template_params.to_h.symbolize_keys))
  end

  def destroy
    render_result(service.destroy(params[:id]))
  end

  private

  def render_result(result)
    return render json: { template: result.template } if result.success?

    # 422 e não 502: o que volta daqui é quase sempre algo que o operador
    # escreveu — nome repetido, categoria que não combina com o texto — e é ele
    # quem corrige.
    render json: { error: result.error }, status: :unprocessable_entity
  end

  def service
    @service ||= Whatsapp::TemplateManagementService.new(@channel)
  end

  def set_channel
    inbox = Current.account.inboxes.find(params[:inbox_id])
    @channel = inbox.channel
    return if @channel.is_a?(Channel::Whatsapp) && @channel.provider == 'whatsapp_cloud'

    # WAHA não tem template: é API não oficial. Dizer isso é melhor do que
    # deixar a tela chamar a Meta com credencial que não existe.
    render json: { error: 'cloud_provider_required' }, status: :unprocessable_entity
  end

  def template_params
    params.require(:template).permit(:name, :category, :language, :body)
  end

  # Submeter template compromete o número da conta inteira: recusa repetida
  # derruba a qualidade, e a qualidade define o limite diário de envio.
  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end
end
