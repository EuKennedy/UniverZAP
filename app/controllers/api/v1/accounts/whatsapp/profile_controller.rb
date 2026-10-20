# "Meu WhatsApp": perfil e status (stories) do número da empresa, direto do
# painel, sem depender do celular na mão.
#
# Não há Pundit policy aqui de propósito: o recurso manipulado não é um model
# desta base, é a conta de WhatsApp remota. O `check_authorization` herdado
# deriva o model pelo nome do controller e explodiria procurando uma classe
# `Profile`, então a autorização é feita pelo mesmo before_action que os outros
# controllers de administração desta base usam.
class Api::V1::Accounts::Whatsapp::ProfileController < Api::V1::Accounts::BaseController
  before_action :ensure_administrator
  before_action :resolve_waha_inbox, except: [:inboxes]
  before_action :resolve_media_url, only: [:update_picture]

  rescue_from Whatsapp::WahaSessionService::WahaError, with: :render_waha_error
  rescue_from Whatsapp::WahaInboxResolver::NotWahaInboxError, with: :render_not_waha_inbox

  # GET /api/v1/accounts/:account_id/whatsapp/profile/inboxes
  def inboxes
    render json: { payload: resolver.waha_inboxes.map { |inbox| inbox_payload(inbox) } }
  end

  # GET /api/v1/accounts/:account_id/whatsapp/profile?inbox_id=
  def show
    # Versões da WAHA que respondem sem content-type JSON devolvem a string
    # crua, e aí ler chaves dela levantaria erro em vez de mostrar a tela.
    profile = @waha_service.profile
    profile = {} unless profile.is_a?(Hash)
    render json: {
      inbox_id: @inbox.id,
      id: profile['id'],
      name: profile['name'],
      picture: profile['picture']
    }
  end

  def update_name
    name = params.require(:name).to_s.strip
    @waha_service.update_profile_name(name)
    render json: { name: name }
  end

  def update_about
    about = params.require(:about).to_s.strip
    @waha_service.update_profile_about(about)
    render json: { about: about }
  end

  def update_picture
    @waha_service.update_profile_picture(url: @media_url)
    render json: { success: true }
  end

  def delete_picture
    @waha_service.delete_profile_picture
    render json: { success: true }
  end

  private

  def ensure_administrator
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  def resolver
    @resolver ||= Whatsapp::WahaInboxResolver.new(Current.account)
  end

  # O session_name nunca vem do request: ele é derivado da inbox, que por sua
  # vez só é procurada dentro da conta autenticada.
  def resolve_waha_inbox
    @inbox, @waha_service = resolver.resolve!(params.require(:inbox_id))
  end

  # A WAHA baixa a mídia por URL, então reaproveitamos o mesmo caminho do envio
  # de anexo (blob do ActiveStorage + URL assinada) em vez de inventar outro
  # armazenamento. O blob chega como signed_id do upload que o painel já faz.
  def resolve_media_url
    blob = ActiveStorage::Blob.find_signed(params[:blob_id].to_s)
    return render_unprocessable('inbox.whatsapp.waha.media_not_found') if blob.blank?
    return render_unprocessable('inbox.whatsapp.waha.media_wrong_type') unless expected_media_type?(blob)

    @media_url = Whatsapp::WahaMediaUrl.for(blob)
  end

  # Recusa clara em vez de um 4xx cru da WAHA ao mandar um PDF como foto.
  def expected_media_type?(blob)
    blob.content_type.to_s.start_with?('image/')
  end

  def inbox_payload(inbox)
    {
      id: inbox.id,
      name: inbox.name,
      channel_type: inbox.channel_type,
      session_name: resolver.session_name_for(inbox)
    }
  end

  def render_unprocessable(key)
    render json: { error: I18n.t(key) }, status: :unprocessable_entity
  end

  def render_not_waha_inbox(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def render_waha_error(error)
    render json: { error: Whatsapp::WahaErrorMessage.humanize(error.message) }, status: :unprocessable_entity
  end
end
