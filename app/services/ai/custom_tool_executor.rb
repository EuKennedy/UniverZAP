# Executes an agent's own Ai::CustomTool integrations inside the Athenas tool
# loop. `call(name, input) -> String` is the contract Ai::Agent::ToolLoopService
# feeds back to Claude as tool_result content.
#
# It only ever sees the tools it was handed, and the caller scopes those to ONE
# agent — so a workspace's integrations can never leak into another's
# conversation.
#
# Never raises: an integration failure is returned as data so Claude can
# apologise and keep the conversation moving, exactly like the belezaki tools.
class Ai::CustomToolExecutor
  # A hostname can pass the model's save-time check and still RESOLVE to private
  # space (DNS rebinding), so the resolved ip is re-checked here at call time.
  # Mirrors Captain::Tools::HttpTool.
  PRIVATE_IP_RANGES = [
    IPAddr.new('127.0.0.0/8'), IPAddr.new('10.0.0.0/8'), IPAddr.new('172.16.0.0/12'),
    IPAddr.new('192.168.0.0/16'), IPAddr.new('169.254.0.0/16'),
    IPAddr.new('::1'), IPAddr.new('fc00::/7'), IPAddr.new('fe80::/10')
  ].freeze
  MAX_RESPONSE_BYTES = 1.megabyte
  OPEN_TIMEOUT = 8
  READ_TIMEOUT = 20

  def initialize(tools)
    @tools = Array(tools).index_by(&:slug)
    @performed_write = false
  end

  # The Anthropic tool schemas for the tools this executor can run.
  def definitions
    @tools.values.map(&:to_tool_definition)
  end

  # True once a POST tool has been ATTEMPTED this turn. Set before the HTTP call
  # on purpose: a timeout may still have hit the endpoint, so the turn must be
  # treated as non-replayable either way (mirrors the belezaki booking guard).
  def performed_write?
    @performed_write
  end

  def call(name, input)
    tool = @tools[name]
    return error("A ferramenta #{name} não existe.") if tool.nil?

    run(tool, input || {})
  rescue Ai::CustomTool::TemplateError => e
    # Must precede the generic clause. This is the operator's configuration, not
    # a bad day for their endpoint, and saying so is the difference between the
    # agent inventing a workaround and the problem being fixable: a URL that
    # references a parameter the tool never declares fails on EVERY call, before
    # the request is even made.
    Rails.logger.error("[Athenas integration] tool=#{name} misconfigured: #{e.message}")
    error("A ferramenta #{name} está mal configurada e não pode ser usada: #{e.message}. " \
          'Não tente outra vez nem invente os dados: diga que vai confirmar com a equipe.')
  rescue StandardError => e
    Rails.logger.error("[Athenas integration] tool=#{name} #{e.class}: #{e.message}")
    error('Não consegui completar essa ação agora.')
  end

  private

  def run(tool, input)
    @performed_write = true if tool.http_method == 'POST'
    uri = safe_uri!(tool.build_request_url(input))
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = request(tool, uri, input)
    log_call(tool, uri, response, started_at, input)
    body = tool.format_response(response.body.to_s)
    body.presence || empty_response_error(tool, response)
  end

  # One line per call. Until now a tool that answered 200 with an empty list and
  # a tool that was never reachable looked identical from the outside: the agent
  # just said it could not find anything, and there was no way to tell which had
  # happened. Param KEYS only, never values — a query string carries whatever
  # the customer typed.
  def log_call(tool, uri, response, started_at, input)
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    Rails.logger.info(
      "[Athenas integration] tool=#{tool.slug} #{tool.http_method} #{uri.host}#{uri.path} " \
      "params=#{input.keys.sort.join(',')} http=#{response.code} " \
      "bytes=#{response.body.to_s.bytesize} #{elapsed_ms}ms"
    )
  end

  # An endpoint that answers with an empty body tells Claude nothing: the blank
  # tool_result reads as "no information" rather than "this failed", so it
  # retries the identical call until the loop cap and the turn dies with no
  # answer. Naming the failure lets it correct the call — most often a required
  # parameter the endpoint silently refused.
  def empty_response_error(tool, response)
    Rails.logger.warn("[Athenas integration] tool=#{tool.slug} empty body http=#{response.code}")
    error("A ferramenta #{tool.slug} respondeu vazio (HTTP #{response.code}). " \
          'Confira se todos os parâmetros obrigatórios foram enviados.')
  end

  def safe_uri!(url)
    uri = parse_uri(url)
    raise "non-https endpoint: #{uri.scheme}" unless uri.scheme == 'https'

    ip = IPAddr.new(Resolv.getaddress(uri.host))
    raise "private ip blocked: #{uri.host}" if PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }

    uri
  end

  # Escaping is a REPAIR, attempted only after a parse actually failed, never as
  # a blanket transform. A template written the documented way already pipes its
  # value through Liquid's url_encode, and escaping that a second time would
  # turn a space into %2520 and break a search that works today. This is only
  # for the operator who left the filter out and whose URL therefore arrives
  # with a raw space in it.
  def parse_uri(url)
    URI.parse(url)
  rescue URI::InvalidURIError
    URI.parse(URI::DEFAULT_PARSER.escape(url))
  end

  def request(tool, uri, input)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.max_retries = 0
    req = build_request(tool, uri, input)
    apply_auth(tool, req)
    verify_size!(http.request(req))
  end

  def build_request(tool, uri, input)
    return Net::HTTP::Get.new(uri.request_uri) unless tool.http_method == 'POST'

    req = Net::HTTP::Post.new(uri.request_uri)
    # A POST always carries a JSON body: the configured request_template when one
    # exists, otherwise the model's raw input. Without this fallback a tool like
    # univercart's create-link — whose body IS the input `{items:[...]}` — would
    # be posted empty, and the cart would come back with nothing in it.
    req.body = tool.build_request_body(input).presence || input.to_json
    req['Content-Type'] = 'application/json'
    req
  end

  def apply_auth(tool, req)
    tool.build_auth_headers.each { |key, value| req[key] = value }
    creds = tool.build_basic_auth_credentials
    req.basic_auth(*creds) if creds
  end

  def verify_size!(response)
    raise 'response too large' if response.body.to_s.bytesize > MAX_RESPONSE_BYTES

    response
  end

  def error(message)
    { error: true, message: message }.to_json
  end
end
