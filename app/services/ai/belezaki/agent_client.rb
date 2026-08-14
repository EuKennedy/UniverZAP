# Server-to-server client for the belezaki agent API (salon scheduling).
#
# Auth: shared UNIVERZAP_AGENT_API_KEY + the salon id, which comes from the
# agent's own Ai::Belezaki::Connection. Never resolved from the account here:
# that is what allowed a cached, arbitrary row to point an agent at the wrong
# salon, and it is why the id is frozen on the connection instead.
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

  # This customer's appointments, scoped by their phone. An id belonging to
  # somebody else answers 404 exactly like one that does not exist, so the agent
  # cannot go fishing through other people's agendas.
  def appointments(phone:, from: nil, to: nil)
    get('/appointments', phone: phone, from: from, to: to)
  end

  def reschedule_appointment(id, payload)
    request(:patch, "/appointments/#{CGI.escape(id.to_s)}", { body: payload.to_json }, WRITE_TIMEOUT)
  end

  # POST, so the salon answers 201 rather than 200. A success check written as
  # `== 200` would turn every completed cancellation into a silent error.
  # Opens the salon's till record. Also a POST, so also 201 — the same trap the
  # cancellation carries.
  def open_comanda(id, payload)
    request(:post, "/appointments/#{CGI.escape(id.to_s)}/comanda", { body: payload.to_json }, WRITE_TIMEOUT)
  end

  def cancel_appointment(id, payload)
    request(:post, "/appointments/#{CGI.escape(id.to_s)}/cancel", { body: payload.to_json }, WRITE_TIMEOUT)
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
      return decode(response) if response.success?

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

  # HTTParty only parses when the response carries a JSON content-type, and the
  # whole error contract would then hang off that header: a 409 arriving without
  # it collapses `slot_taken` — a normal turn in a booking conversation — into a
  # generic http_409, and the agent stops offering another time.
  def decode(response)
    parsed = response.parsed_response
    return parsed unless parsed.is_a?(String)

    JSON.parse(parsed)
  rescue JSON::ParserError
    parsed
  end

  def build_error(response)
    body = decode(response)
    status = response.code.to_i
    # Falls back to the code when the salon sends none: `entitlement_inactive`
    # arrives as a bare {"error": ...}, and an empty message would be written to
    # the connection as a blank last_error — which the card reads as "no failure"
    # and shows nothing.
    return Error.new(body['message'].presence || body['error'], code: body['error'], status: status) if conflict_shape?(body)
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
