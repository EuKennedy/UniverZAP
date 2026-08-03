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
  end

  # The Anthropic tool schemas for the tools this executor can run.
  def definitions
    @tools.values.map(&:to_tool_definition)
  end

  def call(name, input)
    tool = @tools[name]
    return error("A ferramenta #{name} não existe.") if tool.nil?

    run(tool, input || {})
  rescue StandardError => e
    Rails.logger.error("[Athenas integration] tool=#{name} #{e.class}: #{e.message}")
    error('Não consegui completar essa ação agora.')
  end

  private

  def run(tool, input)
    uri = safe_uri!(tool.build_request_url(input))
    tool.format_response(request(tool, uri, input).body.to_s)
  end

  def safe_uri!(url)
    uri = URI.parse(url)
    raise "non-https endpoint: #{uri.scheme}" unless uri.scheme == 'https'

    ip = IPAddr.new(Resolv.getaddress(uri.host))
    raise "private ip blocked: #{uri.host}" if PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }

    uri
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

    req  = Net::HTTP::Post.new(uri.request_uri)
    body = tool.build_request_body(input)
    if body.present?
      req.body = body
      req['Content-Type'] = 'application/json'
    end
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
