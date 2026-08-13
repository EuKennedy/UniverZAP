# Server-to-server client for the belezaki agent API (salon scheduling).
#
# Auth: shared UNIVERZAP_AGENT_API_KEY + the account's belezaki external_user_id
# (which salon). Built per-connection now that an agent binds to one salon
# explicitly; `.for_account` remains for callers that still resolve by account.
class Ai::Belezaki::AgentClient
  # Carries the CODE, not just the message. Three different error shapes come
  # out of this API and only one of them is the documented one, so matching on
  # the message string — which the field spec explicitly forbids — would collapse
  # "the slot is taken" into "something went wrong".
  class Error < StandardError
    attr_reader :code, :status, :validation

    def initialize(message, code: nil, status: nil, validation: nil)
      super(message)
      @code = code
      @status = status
      @validation = validation
    end
  end

  # The Nest app mounts everything under a global `api` prefix
  # (`app.setup.ts:79`), so `/agent/v1` is a 404 from the proxy. Overridable
  # because the host itself is routed outside the repository.
  PREFIX = ENV.fetch('BELEZAKI_AGENT_PREFIX', '/api/agent/v1').freeze

  # 10s to read, 25s to write. Their statements are cut at 20s, and a client
  # timeout SHORTER than the server's means giving up on a request that is still
  # going to create an appointment.
  READ_TIMEOUT = 10
  WRITE_TIMEOUT = 25

  RETRIABLE = [429, 500, 502, 503, 504].freeze
  # Two, not five: every retry of a write is a chance at a duplicate appointment
  # if the idempotency key ever fails to do its job.
  MAX_ATTEMPTS = 2

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

  # Write timeout despite being a read: this one runs computeSlots 31 times per
  # professional inside a single transaction, and is the slowest route they have.
  def availability_month(service_id:, month:, professional_id: nil)
    get('/availability-month', { service_id: service_id, month: month, professional_id: professional_id },
        WRITE_TIMEOUT)
  end

  def create_appointment(payload)
    request(:post, '/appointments', { body: payload.to_json }, WRITE_TIMEOUT)
  end

  private

  def get(path, params = {}, timeout = READ_TIMEOUT)
    request(:get, path, { query: params.compact }, timeout)
  end

  def request(method, path, http_options, timeout)
    url = "#{self.class.base_url}#{PREFIX}#{path}"
    attempt = 0
    begin
      attempt += 1
      response = HTTParty.public_send(method, url, **http_options, headers: headers, timeout: timeout)
      return response.parsed_response if response.success?

      raise build_error(response)
    rescue Error => e
      raise e unless retriable?(e.status) && attempt < MAX_ATTEMPTS

      sleep(backoff(attempt))
      retry
    rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
      raise Error.new(e.message, code: 'network') if attempt >= MAX_ATTEMPTS

      sleep(backoff(attempt))
      retry
    end
  end

  # A 4xx is the server saying the request itself is wrong. Repeating it is
  # waste, and on a write it is a second appointment waiting to happen.
  def retriable?(status)
    RETRIABLE.include?(status.to_i)
  end

  # Jittered so two conversations retrying in the same second do not line up and
  # hit the (per-IP, shared by every salon) rate limit together.
  def backoff(attempt)
    (0.4 * (2**(attempt - 1))) + (rand * 0.2)
  end

  def build_error(response)
    body = response.parsed_response
    status = response.code.to_i
    return Error.new(body['message'].to_s, code: body['error'], status: status) if conflict_shape?(body)
    return validation_error(body, status) if validation_shape?(body)

    message = (body.is_a?(Hash) ? body['message'] : nil).presence || "HTTP #{status}"
    Error.new(message.to_s, code: "http_#{status}", status: status)
  end

  # The book's 409 is the ONE case that answers `{error, message}` with no
  # `statusCode`. It is also the one the agent must recognise, because a taken
  # slot is a normal turn in a conversation, not a failure.
  def conflict_shape?(body)
    body.is_a?(Hash) && body['error'].is_a?(String) && !body.key?('statusCode')
  end

  # NestJS ValidationPipe answers with `message` as an ARRAY, in English. Those
  # strings are for us, never for the customer.
  def validation_shape?(body)
    body.is_a?(Hash) && body['message'].is_a?(Array)
  end

  def validation_error(body, status)
    Error.new('Dados inválidos.', code: 'validation_failed', status: status, validation: body['message'])
  end

  def headers
    {
      'X-Univerzap-Agent-Key' => @api_key,
      'X-Tenant-External-Id' => @external_id,
      'Content-Type' => 'application/json'
    }
  end
end
