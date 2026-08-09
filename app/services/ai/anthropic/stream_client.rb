# Talks to the Anthropic Messages API over Server-Sent Events.
#
# WHY STREAMING. A non-streaming POST parks the socket in ONE blocking read
# until Claude has finished generating the entire answer, so the HTTP read
# timeout stops meaning "is this connection alive" and silently becomes "how
# long is the model allowed to think". Ours was 30 seconds. A tool-loop
# iteration carrying 20k tokens of context and writing a long reply routinely
# needs more than that, so the read blew up, the retry re-sent the identical
# slow request twice more, and the customer's turn died after burning three
# full generations. That is the "o agente trava quando precisa consultar algo"
# report.
#
# With SSE the server emits a delta or a ping every few hundred milliseconds,
# so the timeout goes back to measuring a dead connection and the model can
# take as long as it needs.
#
# Returns an object that quacks like HTTParty::Response (code, success?,
# parsed_response, body) carrying the same hash the non-streaming endpoint
# would have produced, so no caller had to change.
class Ai::Anthropic::StreamClient
  OPEN_TIMEOUT = 10

  # Silence BETWEEN two chunks, not the duration of the answer. Anthropic pings
  # while it thinks, so a whole minute of nothing means the connection is gone.
  IDLE_TIMEOUT = 60

  # Anthropic reports a mid-stream failure as an SSE `error` frame on an HTTP
  # 200. Mapping it back to a status code is what keeps Ai::ClaudeService's
  # retry and its Error/TransientError classification working unchanged.
  STREAM_ERROR_STATUS = {
    'overloaded_error' => 529,
    'rate_limit_error' => 429,
    'api_error' => 500
  }.freeze
  DEFAULT_STREAM_ERROR_STATUS = 500

  Response = Struct.new(:code, :parsed_response, :body) do
    def success?
      code.to_i.between?(200, 299)
    end
  end

  def initialize(url:, headers:, payload:)
    @uri = URI.parse(url)
    @headers = headers
    @payload = payload.merge(stream: true)
  end

  def perform
    result = nil
    http.start do |connection|
      connection.request(build_request) do |response|
        result = success?(response) ? collect(response) : failure(response)
      end
    end
    result
  end

  private

  def success?(response)
    response.code.to_i.between?(200, 299)
  end

  def http
    client = Net::HTTP.new(@uri.host, @uri.port)
    client.use_ssl = @uri.scheme == 'https'
    client.open_timeout = OPEN_TIMEOUT
    client.read_timeout = IDLE_TIMEOUT
    client
  end

  def build_request
    request = Net::HTTP::Post.new(@uri)
    @headers.each { |key, value| request[key] = value }
    request['accept'] = 'text/event-stream'
    # Net::HTTP asks for gzip by default. A compressed stream is buffered before
    # it is flushed, which would hand back exactly the long silence streaming
    # exists to avoid.
    request['accept-encoding'] = 'identity'
    request.body = @payload.to_json
    request
  end

  # SSE frames are separated by a blank line, but chunks arrive on TCP
  # boundaries, so the tail of a half-delivered frame has to survive until the
  # rest of it shows up. The buffer stays BINARY for exactly that reason: a
  # multi-byte character split across two chunks would otherwise raise on
  # append. The frame separator is ASCII, so a frame can never be cut inside a
  # character and it is safe to reinterpret as UTF-8 once complete.
  def collect(response)
    accumulator = Ai::Anthropic::StreamAccumulator.new
    buffer = String.new(encoding: Encoding::BINARY)
    response.read_body do |chunk|
      # `.b` and not a bare append: a chunk that arrives tagged UTF-8 and ends
      # mid-character cannot be concatenated onto a binary buffer.
      buffer << chunk.b
      drain(buffer, accumulator)
    end
    accumulator.error.presence ? stream_error(accumulator.error) : Response.new(200, accumulator.to_message, nil)
  end

  def drain(buffer, accumulator)
    while (boundary = buffer.index("\n\n"))
      frame = buffer.slice!(0..boundary + 1)
      accumulator.ingest(frame.force_encoding(Encoding::UTF_8))
    end
  end

  def stream_error(error)
    status = STREAM_ERROR_STATUS.fetch(error['type'], DEFAULT_STREAM_ERROR_STATUS)
    Response.new(status, { 'error' => error }, error.to_json)
  end

  def failure(response)
    body = response.read_body.to_s
    Response.new(response.code.to_i, safe_parse(body), body)
  end

  def safe_parse(body)
    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end
end
