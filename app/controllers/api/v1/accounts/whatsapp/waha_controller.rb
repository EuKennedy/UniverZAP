class Api::V1::Accounts::Whatsapp::WahaController < Api::V1::Accounts::BaseController
  before_action :ensure_waha_configured

  # POST /api/v1/accounts/:account_id/whatsapp/waha/sessions
  # Creates a new WAHA session for this account and returns the resolved session_name.
  def create_session
    name = sanitized_session_name
    service = session_service(name)
    if service.session_exists?
      render json: { error: I18n.t('inbox.whatsapp.waha.session_exists') }, status: :unprocessable_entity
      return
    end

    service.create_session(webhook_url: webhook_url)
    render json: { session_name: name, status: 'STARTING' }
  rescue Whatsapp::WahaSessionService::WahaError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /api/v1/accounts/:account_id/whatsapp/waha/sessions/:session_name
  def show_session
    service = session_service(params[:session_name])
    session = service.session
    return render(json: { error: 'not_found' }, status: :not_found) unless session

    render json: {
      session_name: session['name'],
      status: session['status'],
      me: session['me']
    }
  end

  # GET /api/v1/accounts/:account_id/whatsapp/waha/sessions/:session_name/qr
  def session_qr
    service = session_service(params[:session_name])
    qr = service.qr_code
    render json: { qr: qr }
  rescue Whatsapp::WahaSessionService::WahaError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/accounts/:account_id/whatsapp/waha/sessions/:session_name/connect_webhook
  # Adopts an existing WAHA session by ensuring our webhook URL is configured on it.
  def connect_existing
    service = session_service(params[:session_name])
    session = service.session
    return render(json: { error: 'not_found' }, status: :not_found) unless session

    service.update_webhook(webhook_url: webhook_url)
    render json: { session_name: session['name'], status: session['status'], me: session['me'] }
  rescue Whatsapp::WahaSessionService::WahaError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/accounts/:account_id/whatsapp/waha/sessions/:session_name/logout
  def logout_session
    service = session_service(params[:session_name])
    service.logout
    head :ok
  rescue Whatsapp::WahaSessionService::WahaError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/accounts/:account_id/whatsapp/waha/sessions/:session_name/install_app
  # Creates an API channel inbox in Chatwoot and installs the WAHA Chatwoot
  # App so WAHA can drive the inbox via Chatwoot's REST API.
  def install_app
    inbox = create_api_inbox(params[:inbox_name].presence || params[:session_name])
    session_service(params[:session_name]).install_chatwoot_app(chatwoot_app_options(inbox))
    render json: { inbox_id: inbox.id, inbox_identifier: inbox.channel.identifier }
  rescue Whatsapp::WahaSessionService::WahaError, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def ensure_waha_configured
    return if ENV['WAHA_BASE_URL'].present? && ENV['WAHA_API_KEY'].present?

    render json: { error: I18n.t('inbox.whatsapp.waha.not_configured') }, status: :service_unavailable
  end

  def session_service(name)
    Whatsapp::WahaSessionService.new(session_name: name)
  end

  # Slug-safe name scoped per-account so different tenants cannot reuse the
  # same WAHA session id by accident.
  def sanitized_session_name
    raw = params.require(:session_name).to_s.downcase
    slug = raw.gsub(/[^a-z0-9-]/, '-').squeeze('-').gsub(/^-|-$/, '')
    "u#{Current.account.id}-#{slug.presence || SecureRandom.hex(4)}"
  end

  def webhook_url
    base = ENV.fetch('FRONTEND_URL', request.base_url)
    "#{base.chomp('/')}/webhooks/waha"
  end

  def create_api_inbox(name)
    ActiveRecord::Base.transaction do
      channel = Current.account.api_channels.create!(
        webhook_url: nil,
        additional_attributes: {
          source: 'waha',
          session_name: params[:session_name]
        }
      )
      Current.account.inboxes.create!(
        name: name.to_s.truncate(60),
        channel: channel,
        lock_to_single_conversation: true
      )
    end
  end

  def current_user_access_token
    token = current_user.access_token || current_user.create_access_token
    token.token
  end

  def chatwoot_app_options(inbox)
    {
      locale: params[:locale].presence || 'pt-BR',
      chatwoot_url: ENV.fetch('FRONTEND_URL', request.base_url),
      account_id: Current.account.id,
      user_token: current_user_access_token,
      inbox_id: inbox.id,
      inbox_identifier: inbox.channel.identifier
    }
  end
end
