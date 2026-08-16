# "Meu WhatsApp": perfil e status (stories) do número da empresa, direto do
# painel, sem depender do celular na mão.
#
# Não há Pundit policy aqui de propósito: o recurso manipulado não é um model
# desta base, é a conta de WhatsApp remota. O `check_authorization` herdado
# deriva o model pelo nome do controller e explodiria procurando uma classe
# `Profile`, então a autorização é feita pelo mesmo before_action que os outros
# controllers de administração desta base usam.
class Api::V1::Accounts::Whatsapp::ProfileController < Api::V1::Accounts::BaseController
  # A URL assinada do blob precisa durar mais que o padrão: quem baixa o
  # arquivo é a WAHA, e um vídeo de status leva mais tempo que uma foto.
  MEDIA_URL_TTL = 15.minutes

  # O tipo esperado por ação, para o operador receber uma recusa clara em vez
  # de um 4xx cru da WAHA ao mandar um PDF como foto de perfil.
  EXPECTED_MEDIA_TYPE = {
    'update_picture' => 'image',
    'publish_image_status' => 'image',
    'publish_video_status' => 'video'
  }.freeze

  HEX_COLOR = /\A#[0-9a-fA-F]{6}\z/

  before_action :ensure_administrator
  before_action :resolve_waha_inbox, except: [:inboxes]
  before_action :resolve_media_url, only: [:update_picture, :publish_image_status, :publish_video_status]
  before_action :validate_background_color, only: [:publish_text_status, :publish_video_status]

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

  def publish_text_status
    @waha_service.send_status_text(text: params.require(:text).to_s, background_color: background_color)
    render json: { success: true }
  end

  def publish_image_status
    @waha_service.send_status_image(url: @media_url, caption: params[:caption].presence, mimetype: @media_mimetype)
    render json: { success: true }
  end

  def publish_video_status
    @waha_service.send_status_video(url: @media_url, mimetype: @media_mimetype, background_color: background_color)
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

    ActiveStorage::Current.url_options = Rails.application.routes.default_url_options if ActiveStorage::Current.url_options.blank?
    @media_mimetype = blob.content_type
    @media_url = blob.url(expires_in: MEDIA_URL_TTL)
  end

  def expected_media_type?(blob)
    blob.content_type.to_s.start_with?("#{EXPECTED_MEDIA_TYPE.fetch(action_name)}/")
  end

  def validate_background_color
    color = params[:background_color].to_s
    return if color.blank? || color.match?(HEX_COLOR)

    render_unprocessable('inbox.whatsapp.waha.invalid_background_color')
  end

  def background_color
    params[:background_color].presence
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
    render json: { error: humanized_waha_error(error.message) }, status: :unprocessable_entity
  end

  # A WahaError carrega método, path e o corpo cru da resposta. Para a tela
  # interessa o que a WAHA respondeu, então extraímos a mensagem do JSON e só
  # caímos no texto inteiro quando não há nada estruturado para mostrar.
  def humanized_waha_error(message)
    payload = message[/\{.*\}/m]
    parsed = payload.present? ? JSON.parse(payload) : nil
    return message unless parsed.is_a?(Hash)

    (parsed['message'] || parsed['error']).to_s.presence || message
  rescue JSON::ParserError
    message
  end
end
