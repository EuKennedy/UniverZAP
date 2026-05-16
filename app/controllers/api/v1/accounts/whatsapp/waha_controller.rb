class Api::V1::Accounts::Whatsapp::WahaController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
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
    session = service.get_session
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
    session = service.get_session
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

  private

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

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
    slug = raw.gsub(/[^a-z0-9-]/, '-').gsub(/-+/, '-').gsub(/^-|-$/, '')
    "u#{Current.account.id}-#{slug.presence || SecureRandom.hex(4)}"
  end

  def webhook_url
    base = ENV.fetch('FRONTEND_URL', request.base_url)
    "#{base.chomp('/')}/webhooks/waha"
  end
end
