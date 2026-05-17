class Whatsapp::WahaSessionService
  class WahaError < StandardError; end

  def initialize(session_name: nil, base_url: nil, api_key: nil)
    @session_name = session_name
    @base_url = (base_url || ENV.fetch('WAHA_BASE_URL', nil))&.chomp('/')
    @api_key = api_key || ENV.fetch('WAHA_API_KEY', nil)
  end

  def list_sessions
    request(:get, '/api/sessions')
  end

  def session
    request(:get, "/api/sessions/#{@session_name}")
  rescue WahaError
    nil
  end

  def session_exists?
    !session.nil?
  end

  def create_session(webhook_url:)
    payload = {
      name: @session_name,
      start: true,
      config: {
        webhooks: [
          {
            url: webhook_url,
            events: %w[message message.any message.ack session.status],
            retries: { attempts: 3, delaySeconds: 2, policy: 'constant' }
          }
        ],
        ignore: { status: true, groups: false, channels: false, broadcast: true }
      }
    }
    request(:post, '/api/sessions/', body: payload)
  end

  def start_session
    request(:post, "/api/sessions/#{@session_name}/start")
  end

  def stop_session
    request(:post, "/api/sessions/#{@session_name}/stop")
  end

  def restart_session
    request(:post, "/api/sessions/#{@session_name}/restart")
  end

  def logout
    request(:post, "/api/sessions/#{@session_name}/logout")
  end

  def delete
    request(:delete, "/api/sessions/#{@session_name}")
  end

  def qr_code
    response = HTTParty.get(
      "#{@base_url}/api/#{@session_name}/auth/qr?format=image",
      headers: headers,
      timeout: 10
    )
    raise WahaError, "WAHA QR failed: #{response.code} #{response.body.to_s.truncate(200)}" unless response.success?

    extract_qr_data_url(response)
  end

  def update_webhook(webhook_url:)
    payload = {
      config: {
        webhooks: [
          {
            url: webhook_url,
            events: %w[message message.any message.ack session.status]
          }
        ]
      }
    }
    request(:put, "/api/sessions/#{@session_name}", body: payload)
  end

  def send_text(chat_id:, text:)
    request(:post, '/api/sendText', body: { session: @session_name, chatId: chat_id, text: text })
  end

  def send_media(chat_id:, type:, url:, caption: nil, filename: nil)
    body = {
      session: @session_name,
      chatId: chat_id,
      file: { url: url, filename: filename }.compact
    }
    body[:caption] = caption if caption.present? && %w[image video document].include?(type)
    endpoint = {
      'image' => '/api/sendImage',
      'video' => '/api/sendVideo',
      'audio' => '/api/sendVoice',
      'document' => '/api/sendFile'
    }.fetch(type, '/api/sendFile')
    request(:post, endpoint, body: body)
  end

  def fetch_contact(chat_id:)
    request(:get, "/api/contacts?session=#{@session_name}&contactId=#{chat_id}")
  rescue WahaError
    nil
  end

  # Installs the built-in WAHA Chatwoot App and points it at the given Chatwoot
  # account + inbox. WAHA then drives the inbox via the Chatwoot API, creates
  # the "WhatsApp Integration" command contact, and forwards messages both ways.
  # See https://waha.devlike.pro/docs/apps/chatwoot/
  def install_chatwoot_app(options)
    payload = {
      id: options[:app_id] || "app_#{SecureRandom.hex(12)}",
      session: @session_name,
      app: 'chatwoot',
      config: chatwoot_app_config(options),
      enabled: true
    }
    request(:post, '/api/apps', body: payload)
  end

  def list_apps
    request(:get, "/api/apps?session=#{@session_name}")
  rescue WahaError
    []
  end

  def uninstall_app(app_id)
    request(:delete, "/api/apps/#{app_id}")
  end

  private

  def headers
    {
      'Content-Type' => 'application/json',
      'X-Api-Key' => @api_key
    }
  end

  # WAHA returns either application/json with {mimetype, data} (base64)
  # or raw image/png bytes depending on version.
  def extract_qr_data_url(response)
    content_type = response.headers['content-type'].to_s
    return qr_data_url_from_json(response.parsed_response) if content_type.include?('application/json')

    mime = content_type.split(';').first.presence || 'image/png'
    "data:#{mime};base64,#{Base64.strict_encode64(response.body)}"
  end

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

  def qr_data_url_from_json(parsed)
    data = parsed.is_a?(Hash) ? (parsed['data'] || parsed['value']) : parsed
    mimetype = (parsed.is_a?(Hash) && parsed['mimetype']) || 'image/png'
    data.to_s.start_with?('data:') ? data : "data:#{mimetype};base64,#{data}"
  end

  def request(method, path, body: nil)
    raise WahaError, 'WAHA_BASE_URL/api_key not configured' if @base_url.blank? || @api_key.blank?

    response = perform_http(method, path, body)
    handle_failure!(method, path, response) unless response.success?
    response.parsed_response
  end

  def perform_http(method, path, body)
    options = { headers: headers, timeout: 15 }
    options[:body] = body.to_json if body
    Rails.logger.info("[WAHA] #{method.to_s.upcase} #{path} session=#{@session_name}")
    HTTParty.public_send(method, "#{@base_url}#{path}", options)
  end

  def handle_failure!(method, path, response)
    Rails.logger.error("[WAHA] #{method.to_s.upcase} #{path} -> #{response.code} body=#{response.body.to_s.truncate(500)}")
    raise WahaError, "WAHA #{method} #{path} failed: #{response.code} #{response.body.to_s.truncate(300)}"
  end
end
