# Thin wrapper around the Anthropic Messages API. Uses HTTParty directly so we
# don't depend on any gem version. Designed to log every invocation through the
# Ai::Invocation model for cost tracking.
class Ai::ClaudeService
  class Error < StandardError; end
  # Upstream blip that survived the in-request backoff (Anthropic 5xx/429 or a
  # network timeout). Subclass of Error on purpose: every existing rescuer keeps
  # behaving exactly as before, while background callers can opt into retrying
  # the whole turn later instead of dropping the customer's message.
  class TransientError < Error; end

  API_BASE = 'https://api.anthropic.com'.freeze
  API_VERSION = '2023-06-01'.freeze

  def initialize(assistant:, account: nil)
    @assistant = assistant
    @account = account || assistant&.account
  end

  # `log_context` turns this call into a response-log row instead of a bare cost
  # entry: { user_message:, chunks:, prompt_version:, delivery_status: }. Callers
  # that face a customer pass it; summaries and classifiers do not.
  def chat(messages:, system: nil, conversation: nil, phase: 'main', log_context: nil, **overrides) # rubocop:disable Metrics/ParameterLists
    api_key = @assistant&.resolved_anthropic_key
    raise Error, 'Anthropic API key not configured' if api_key.blank?

    payload = build_payload(messages, system, overrides)
    check_quota!(payload)
    context = { conversation: conversation, phase: phase, log: log_context }
    started_at = Time.zone.now
    response = perform_request(api_key, payload)
    track(response: response, payload: payload, started_at: started_at, context: context)
  rescue Error
    raise
  rescue *RETRYABLE_NET_ERRORS => e
    # Retries inside the request are exhausted, but the failure is still a blip:
    # let a background caller re-run the turn later.
    Rails.logger.error("[Athenas] Claude chat failed (transient): #{e.message}")
    raise TransientError, e.message
  rescue StandardError => e
    Rails.logger.error("[Athenas] Claude chat failed: #{e.message}")
    raise Error, e.message
  end

  private

  # Cap the worst-case cost pre-flight using `max_tokens` from the payload. The
  # actual invocation is debited post-flight against real usage so customers
  # never pay for tokens Claude didn't emit.
  def check_quota!(payload)
    return if @account.blank?

    Ai::QuotaService.check!(account: @account, model: payload[:model], max_output_tokens: payload[:max_tokens])
  end

  def build_payload(messages, system, overrides)
    {
      model: pick(overrides[:model], @assistant&.model, 'claude-sonnet-4-5'),
      max_tokens: pick(overrides[:max_tokens], @assistant&.max_tokens, 1024),
      temperature: pick(overrides[:temperature], @assistant&.temperature, 0.3),
      system: build_system(system),
      messages: cache_messages(messages, overrides[:cache_messages]),
      # Optional Anthropic tool-use (function calling). Absent for every
      # existing caller (compact drops nil), so behaviour is unchanged unless
      # a caller passes `tools:`.
      tools: overrides[:tools]
    }.compact
  end

  def pick(*candidates)
    candidates.compact.first
  end

  # A cache breakpoint on the LAST message, so the whole conversation up to here
  # is reused instead of re-charged.
  #
  # This is where the money is in a tool loop: the system prefix is a couple of
  # thousand tokens, but the message list grows with every tool result — 4k on
  # the first iteration, 22k by the fifth — and each iteration was paying full
  # price for everything the previous one had already sent. Iterations are
  # seconds apart, so the read is as close to guaranteed as caching gets.
  #
  # Off by default: a cache WRITE costs 25% more than a plain token, so it is
  # only worth it where a read is near-certain. The caller decides.
  def cache_messages(messages, enabled)
    return messages unless enabled && messages.present?

    last = messages.last
    marked = last.merge(content: mark_cacheable(last[:content] || last['content']))
    messages[0..-2] + [marked]
  end

  def mark_cacheable(content)
    blocks = content.is_a?(Array) ? content.dup : [{ type: 'text', text: content.to_s }]
    return blocks if blocks.empty?

    tail = blocks.last
    tail = tail.is_a?(Hash) ? tail.dup : { type: 'text', text: tail.to_s }
    blocks[0..-2] + [tail.merge(cache_control: { type: 'ephemeral' })]
  end

  # `system` may be a plain String (sent as-is, never cached) or an Array of
  # segments ordered stable-first. With segments we emit Anthropic system BLOCKS
  # and put a cache breakpoint at the end of the stable ones: everything before
  # it — the tool definitions and that prefix — is reused across calls at a tenth
  # of the input price instead of being re-charged in full every single turn.
  #
  # The caller owns the split, because only it knows which parts are identical
  # between turns. A prefix under the model's minimum (1024 tokens on Sonnet) is
  # simply not cached by Anthropic — no error, no behaviour change.
  def build_system(system)
    return system unless system.is_a?(Array)

    segments = system.map(&:to_s).reject(&:blank?)
    return nil if segments.empty?
    return segments.first if segments.one?

    [
      { type: 'text', text: segments[0..-2].join("\n\n"), cache_control: { type: 'ephemeral' } },
      { type: 'text', text: segments.last }
    ]
  end

  # Exponential backoff on transient failures (timeouts, 5xx, rate limit).
  # Three quick attempts — 0s, ~0.5s, ~1.5s — keeps the user-perceived
  # latency tolerable while soaking up Anthropic blips.
  # DNS (SocketError), TLS handshake and connection-refused blips are just as
  # transient as a timeout — classifying them as permanent used to drop the
  # customer's turn for good. Mirrors the belezaki client's list.
  RETRYABLE_NET_ERRORS = [
    Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED,
    SocketError, OpenSSL::SSL::SSLError, HTTParty::Error
  ].freeze
  MAX_RETRY_ATTEMPTS = 3

  def perform_request(api_key, payload)
    attempts = 0
    begin
      attempts += 1
      response = post_to_claude(api_key, payload)
      # Exhausted retries return the response as-is: `track` logs the failed
      # invocation and raises a user-facing Error with the upstream status.
      raise Net::ReadTimeout if retryable_response?(response) && attempts < MAX_RETRY_ATTEMPTS

      response
    rescue *RETRYABLE_NET_ERRORS => e
      raise e if attempts >= MAX_RETRY_ATTEMPTS

      sleep(0.5 * (2**(attempts - 1)))
      retry
    end
  end

  def post_to_claude(api_key, payload)
    HTTParty.post("#{API_BASE}/v1/messages", headers: headers(api_key), body: payload.to_json, timeout: 30)
  end

  def retryable_response?(response)
    response.code >= 500 || response.code == 429
  end

  def headers(api_key)
    {
      'x-api-key' => api_key,
      'anthropic-version' => API_VERSION,
      'content-type' => 'application/json'
    }
  end

  def track(response:, payload:, started_at:, context:)
    duration_ms = ((Time.zone.now - started_at) * 1000).to_i
    unless response.success?
      log_failed(payload: payload, response: response, duration_ms: duration_ms, context: context)
      raise_upstream_error(response)
    end
    parsed = response.parsed_response
    invocation = log_success(payload: payload, parsed: parsed, duration_ms: duration_ms, context: context)
    {
      content: extract_text(parsed),
      tool_uses: extract_tool_uses(parsed),
      model: parsed['model'],
      stop_reason: parsed['stop_reason'],
      # The log row this call produced, so the caller can enrich it with what
      # only it knows (final text, confidence, guardrail flags) and the job can
      # flip it to delivered.
      invocation: invocation,
      raw: parsed
    }
  end

  # Surface only the upstream message field — the full body can echo user
  # prompts or stray request headers and would otherwise leak straight into the
  # dashboard alert. 5xx/429 that survived the in-request backoff are classified
  # transient so a background caller can retry the turn; 4xx stays permanent
  # (retrying a malformed request or a bad key never helps).
  def raise_upstream_error(response)
    parsed_err = (response.parsed_response.is_a?(Hash) ? response.parsed_response : {})['error'] || {}
    message = parsed_err['message'].presence || "HTTP #{response.code}"
    error_class = retryable_response?(response) ? TransientError : Error
    raise error_class, "Claude API #{response.code}: #{message.to_s.truncate(200)}"
  end

  def extract_text(parsed)
    blocks = parsed['content'] || []
    blocks.filter_map { |b| b['text'] if b['type'] == 'text' }.join
  end

  # Tool-use blocks Claude wants executed before it can answer. Empty for
  # plain text replies. Each: { 'id', 'name', 'input' }.
  def extract_tool_uses(parsed)
    blocks = parsed['content'] || []
    blocks.select { |b| b['type'] == 'tool_use' }
  end

  # Returns the created row so the caller can enrich it. Logging failures are
  # still swallowed (a billing or audit hiccup must never eat the reply), but
  # they now return nil explicitly instead of leaking the rescue value.
  def log_success(payload:, parsed:, duration_ms:, context:)
    usage = parsed['usage'] || {}
    tokens = [usage['input_tokens'].to_i, usage['output_tokens'].to_i]
    cents_brl = cost_cents_brl(payload[:model], tokens, usage)
    invocation = recorder(context).success(
      payload: payload, usage: usage, duration_ms: duration_ms, tokens: tokens, cents_brl: cents_brl
    )
    # Debit the operator's BRL balance against the actual tokens Claude
    # reported. We swallow ledger errors so a billing hiccup never eats
    # the chat reply — the alert still goes to logs.
    debit_credits(invocation, payload[:model], tokens, cents_brl)
    invocation
  rescue StandardError => e
    Rails.logger.error("[Athenas] invocation logging failed: #{e.message}")
    nil
  end

  def recorder(context)
    Ai::InvocationRecorder.new(assistant: @assistant, account: @account, context: context)
  end

  # Cached tokens are reported outside `input_tokens`, and the operator is
  # charged the cheap cache rate for them — passing the saving through is the
  # entire point of turning caching on.
  def cost_cents_brl(model, tokens, usage = {})
    Ai::PricingCalculator.cost_cents_brl(
      model: model, input_tokens: tokens.first, output_tokens: tokens.last,
      cache_write_tokens: usage['cache_creation_input_tokens'].to_i,
      cache_read_tokens: usage['cache_read_input_tokens'].to_i
    )
  end

  def debit_credits(invocation, model, tokens, cents_brl)
    return if @account.blank? || cents_brl.zero?

    Ai::CreditLedger.new(@account).debit!(
      invocation: invocation,
      cents_brl: cents_brl,
      description: "Claude #{model} #{tokens.first}+#{tokens.last} tokens"
    )
  rescue StandardError => e
    Rails.logger.error("[Athenas] credit debit failed account=#{@account&.id}: #{e.message}")
  end

  def log_failed(payload:, response:, duration_ms:, context:)
    recorder(context).failure(payload: payload, response: response, duration_ms: duration_ms)
  rescue StandardError => e
    Rails.logger.error("[Athenas] failure logging crashed: #{e.message}")
  end
end
