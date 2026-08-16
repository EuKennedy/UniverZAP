# Instalação do Chatwoot App embutido da WAHA, que é o que faz a WAHA dirigir
# uma inbox pela nossa API REST. Docs: https://waha.devlike.pro/docs/apps/chatwoot/
#
# Saiu de WahaSessionService para um módulo próprio quando a classe passou do
# teto de ClassLength: é o bloco menos ligado ao resto de lá, que cuida do ciclo
# de vida da sessão e do envio de mensagem. O cliente HTTP continua sendo um só.
module Whatsapp::WahaChatwootApp
  # Install WAHA's built-in Chatwoot App, replacing any stale Chatwoot app on
  # this session that points at our own Chatwoot URL. Other Chatwoot installs
  # sharing the session are left alone.
  def install_chatwoot_app(options)
    uninstall_existing_chatwoot_apps(matching_url: options[:chatwoot_url])
    perform_app_install(options)
  rescue Whatsapp::WahaSessionService::WahaError => e
    stale_id = e.message[/Chatwoot app with ID '([a-z0-9_]+)'/i, 1]
    raise unless stale_id

    Rails.logger.warn("[WAHA] forcing uninstall of stale Chatwoot app #{stale_id} after install conflict")
    safe_uninstall_app(stale_id)
    perform_app_install(options)
  end

  def perform_app_install(options)
    payload = {
      id: options[:app_id] || "app_#{SecureRandom.hex(12)}",
      session: @session_name, app: 'chatwoot',
      config: chatwoot_app_config(options), enabled: true
    }
    request(:post, '/api/apps', body: payload)
  end

  def uninstall_existing_chatwoot_apps(matching_url: nil)
    apps = list_apps
    return unless apps.is_a?(Array)

    target = matching_url.to_s.chomp('/')
    apps.select { |app| chatwoot_app_matches?(app, target) }
        .each { |app| safe_uninstall_app(app['id']) }
  end

  def safe_uninstall_app(app_id)
    return if app_id.blank?

    uninstall_app(app_id)
  rescue Whatsapp::WahaSessionService::WahaError => e
    Rails.logger.warn("[WAHA] failed to uninstall stale Chatwoot app #{app_id}: #{e.message}")
  end

  def chatwoot_app_matches?(app, target_url)
    return false unless app.is_a?(Hash) && app['app'] == 'chatwoot'
    return false if app['session'] && app['session'] != @session_name

    target_url.blank? || app.dig('config', 'url').to_s.chomp('/') == target_url
  end

  def list_apps
    request(:get, "/api/apps?session=#{@session_name}")
  rescue Whatsapp::WahaSessionService::WahaError
    []
  end

  def uninstall_app(app_id)
    request(:delete, "/api/apps/#{app_id}")
  end

  private

  def chatwoot_app_config(options)
    {
      locale: options[:locale],
      url: options[:chatwoot_url].to_s.chomp('/'),
      accountId: options[:account_id],
      accountToken: options[:user_token],
      inboxId: options[:inbox_id],
      inboxIdentifier: options[:inbox_identifier],
      templates: {},
      commands: { server: true, queue: true },
      conversations: { sort: 'created_newest', status: %w[open pending snoozed resolved] }
    }
  end
end
