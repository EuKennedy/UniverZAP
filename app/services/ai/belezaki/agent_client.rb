# Server-to-server client for the belezaki agent API (salon scheduling).
#
# Auth: shared UNIVERZAP_AGENT_API_KEY + the account's belezaki
# external_user_id (which salon). Built per-account via `.for_account`.
# Returns nil from `.for_account` when the account isn't linked to belezaki
# or the key isn't configured — callers treat nil as "scheduling disabled".
class Ai::Belezaki::AgentClient
  class Error < StandardError; end

  PREFIX = '/agent/v1'.freeze

  def self.base_url
    ENV.fetch('BELEZAKI_AGENT_BASE_URL', 'https://api.belezaki.com.br').chomp('/')
  end

  def self.api_key
    ENV['UNIVERZAP_AGENT_API_KEY'].presence
  end

  def self.for_account(account)
    external_id = Ai::Belezaki::TenantResolver.external_id(account)
    return nil if external_id.blank? || api_key.blank?

    new(external_id: external_id)
  end

  def initialize(external_id:, api_key: self.class.api_key)
    @external_id = external_id
    @api_key = api_key
  end

  def salon
    get('/salon')
  end

  def services
    get('/services')
  end

  def professionals
    get('/professionals')
  end

  def availability(service_id:, date:, professional_id: nil)
    get('/availability', service_id: service_id, date: date, professional_id: professional_id)
  end

  def availability_month(service_id:, month:, professional_id: nil)
    get('/availability-month', service_id: service_id, month: month, professional_id: professional_id)
  end

  def create_appointment(payload)
    post('/appointments', payload)
  end

  private

  def get(path, params = {})
    request(:get, path, { query: params.compact })
  end

  def post(path, body)
    request(:post, path, { body: body.to_json })
  end

  def request(method, path, http_options)
    url = "#{self.class.base_url}#{PREFIX}#{path}"
    response = HTTParty.public_send(method, url, **http_options, headers: headers, timeout: 15)
    parsed = response.parsed_response
    return parsed if response.success?

    message = (parsed.is_a?(Hash) ? parsed['message'] : nil).presence || "HTTP #{response.code}"
    raise Error, message
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
    raise Error, e.message
  end

  def headers
    {
      'X-Univerzap-Agent-Key' => @api_key,
      'X-Tenant-External-Id' => @external_id,
      'Content-Type' => 'application/json'
    }
  end
end
