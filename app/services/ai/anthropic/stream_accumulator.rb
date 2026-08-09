# Rebuilds a complete Anthropic Messages response out of the SSE event stream.
#
# The whole point is that nothing downstream can tell the difference: to_message
# returns the exact hash the non-streaming endpoint would have returned, so
# Ai::ClaudeService#track, the invocation log, the cost calculation and the tool
# loop keep working untouched.
class Ai::Anthropic::StreamAccumulator
  # An `error` frame with no payload still has to read as a failure. An empty
  # hash would test as blank and let a half-written answer through as if the
  # stream had finished normally.
  FALLBACK_ERROR = { 'type' => 'api_error', 'message' => 'stream interrupted' }.freeze

  # A lookup table rather than a case statement: `ping` frames, the ones that
  # keep the connection measurably alive, simply miss the table and cost
  # nothing, and a new Anthropic event type stays a one-line change.
  HANDLERS = {
    'message_start' => :start_message,
    'content_block_start' => :start_block,
    'content_block_delta' => :apply_delta,
    'content_block_stop' => :close_block,
    'message_delta' => :finish_message,
    'error' => :record_error
  }.freeze

  def initialize
    @message = { 'type' => 'message', 'role' => 'assistant', 'content' => [], 'usage' => {} }
    @blocks = {}
    @json_buffers = {}
    @error = nil
  end

  attr_reader :error

  # One raw SSE frame ("event: ...\ndata: {...}"). Anything unparseable is
  # dropped rather than raised: a single malformed frame must not cost the
  # customer the whole answer that came with it.
  def ingest(raw_frame)
    payload = parse(raw_frame)
    return if payload.blank?

    dispatch(payload)
  end

  def to_message
    @message.merge('content' => @blocks.keys.sort.map { |index| @blocks[index] })
  end

  private

  def parse(raw_frame)
    data = raw_frame.each_line.filter_map { |line| line.delete_prefix('data:').strip if line.start_with?('data:') }
    return nil if data.empty?

    JSON.parse(data.join)
  rescue JSON::ParserError
    nil
  end

  def dispatch(payload)
    handler = HANDLERS[payload['type']]
    send(handler, payload) if handler
  end

  # `message_start` carries the input side of the usage, including the two cache
  # counters the ledger bills against; the output count only arrives at the end.
  def start_message(payload)
    message = payload['message']
    return if message.blank?

    @message.merge!(message.slice('id', 'model', 'role', 'stop_reason', 'stop_sequence'))
    @message['usage'] = (message['usage'] || {}).dup
  end

  def start_block(payload)
    block = payload['content_block']
    return if block.blank?

    prepared = block.dup
    prepared['text'] = prepared['text'].to_s if prepared['type'] == 'text'
    @json_buffers[payload['index']] = +'' if prepared['type'] == 'tool_use'
    @blocks[payload['index']] = prepared
  end

  # A tool_use input arrives as a stream of JSON fragments. They are held until
  # the block closes and only parsed then, because half a JSON document is not a
  # document.
  def apply_delta(payload)
    index = payload['index']
    delta = payload['delta']
    return if delta.blank? || @blocks[index].blank?

    case delta['type']
    when 'text_delta'
      @blocks[index]['text'] = "#{@blocks[index]['text']}#{delta['text']}"
    when 'input_json_delta'
      (@json_buffers[index] ||= +'') << delta['partial_json'].to_s
    end
  end

  def close_block(payload)
    index = payload['index']
    buffer = @json_buffers.delete(index)
    return if buffer.nil? || @blocks[index].blank?

    @blocks[index]['input'] = JSON.parse(buffer.presence || '{}')
  rescue JSON::ParserError
    # A truncated tool input is worse than no input: leaving it empty makes the
    # executor fail loudly instead of calling the customer's endpoint with half
    # the arguments.
    @blocks[index]['input'] = {}
  end

  def finish_message(payload)
    @message.merge!(payload['delta'] || {})
    @message['usage'] = @message['usage'].merge(payload['usage'] || {})
  end

  def record_error(payload)
    @error = payload['error'].presence || FALLBACK_ERROR
  end
end
