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
      "#{@base_url}/api/#{@session_name}/auth/qr?format=raw",
      headers: headers,
      timeout: 10
    )
    raise WahaError, "WAHA QR failed: #{response.code}" unless response.success?

    parsed = response.parsed_response
    parsed.is_a?(Hash) ? parsed['value'] : parsed
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

  private

  def headers
    {
      'Content-Type' => 'application/json',
      'X-Api-Key' => @api_key
    }
  end

  def request(method, path, body: nil)
    raise WahaError, 'WAHA_BASE_URL/api_key not configured' if @base_url.blank? || @api_key.blank?

    options = { headers: headers, timeout: 15 }
    options[:body] = body.to_json if body
    response = HTTParty.public_send(method, "#{@base_url}#{path}", options)
    raise WahaError, "WAHA #{method} #{path} failed: #{response.code} #{response.body}" unless response.success?

    response.parsed_response
  end
end
