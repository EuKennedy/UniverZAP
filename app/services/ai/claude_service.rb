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

  def chat(messages:, system: nil, conversation: nil, phase: 'main', **overrides)
    api_key = @assistant&.resolved_anthropic_key
    raise Error, 'Anthropic API key not configured' if api_key.blank?

    payload = build_payload(messages, system, overrides)
    check_quota!(payload)
    started_at = Time.zone.now
    response = perform_request(api_key, payload)
    track(response: response, payload: payload, started_at: started_at, conversation: conversation, phase: phase)
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
      system: system,
      messages: messages,
      # Optional Anthropic tool-use (function calling). Absent for every
      # existing caller (compact drops nil), so behaviour is unchanged unless
      # a caller passes `tools:`.
      tools: overrides[:tools]
    }.compact
  end

  def pick(*candidates)
    candidates.compact.first
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

  def track(response:, payload:, started_at:, conversation:, phase:)
    duration_ms = ((Time.zone.now - started_at) * 1000).to_i
    unless response.success?
      log_failed(payload: payload, response: response, duration_ms: duration_ms, conversation: conversation, phase: phase)
      raise_upstream_error(response)
    end
    parsed = response.parsed_response
    log_success(payload: payload, parsed: parsed, duration_ms: duration_ms, conversation: conversation, phase: phase)
    {
      content: extract_text(parsed),
      tool_uses: extract_tool_uses(parsed),
      model: parsed['model'],
      stop_reason: parsed['stop_reason'],
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

  def log_success(payload:, parsed:, duration_ms:, conversation:, phase:)
    usage = parsed['usage'] || {}
    input_tokens = usage['input_tokens'].to_i
    output_tokens = usage['output_tokens'].to_i
    invocation = record_invocation(
      payload: payload, usage: usage, duration_ms: duration_ms,
      conversation: conversation, phase: phase,
      input_tokens: input_tokens, output_tokens: output_tokens
    )
    # Debit the operator's BRL balance against the actual tokens Claude
    # reported. We swallow ledger errors so a billing hiccup never eats
    # the chat reply — the alert still goes to logs.
    debit_credits(invocation, payload[:model], input_tokens, output_tokens)
  rescue StandardError => e
    Rails.logger.error("[Athenas] invocation logging failed: #{e.message}")
  end

  # Keyword args read fine here so we keep the surface; the parameter
  # list cop fires at 7/5 but every name carries real meaning for the
  # invocation log row — a single options hash would be worse.
  def record_invocation(payload:, usage:, duration_ms:, conversation:, phase:, input_tokens:, output_tokens:) # rubocop:disable Metrics/ParameterLists
    Ai::Invocation.create!(
      ai_assistant: @assistant,
      account: @account,
      conversation_id: conversation&.id,
      phase: phase,
      model: payload[:model],
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cache_read_tokens: usage['cache_read_input_tokens'].to_i,
      cache_write_tokens: usage['cache_creation_input_tokens'].to_i,
      cost_usd: compute_cost(payload[:model], input_tokens, output_tokens),
      duration_ms: duration_ms,
      status: 'success'
    )
  end

  def debit_credits(invocation, model, input_tokens, output_tokens)
    return if @account.blank?

    cents = Ai::PricingCalculator.cost_cents_brl(
      model: model,
      input_tokens: input_tokens,
      output_tokens: output_tokens
    )
    return if cents.zero?

    Ai::CreditLedger.new(@account).debit!(
      invocation: invocation,
      cents_brl: cents,
      description: "Claude #{model} #{input_tokens}+#{output_tokens} tokens"
    )
  rescue StandardError => e
    Rails.logger.error("[Athenas] credit debit failed account=#{@account&.id}: #{e.message}")
  end

  def log_failed(payload:, response:, duration_ms:, conversation:, phase:)
    Ai::Invocation.create!(
      ai_assistant: @assistant,
      account: @account,
      conversation_id: conversation&.id,
      phase: phase,
      model: payload[:model],
      duration_ms: duration_ms,
      status: 'error',
      error_message: "#{response.code}: #{response.body.to_s.truncate(300)}"
    )
  rescue StandardError => e
    Rails.logger.error("[Athenas] failure logging crashed: #{e.message}")
  end

  # Pricing lives in Ai::PricingCalculator (single source of truth) so the
  # telemetry recorded here can never drift from what the ledger debits.
  def compute_cost(model, input_tokens, output_tokens)
    rates = Ai::PricingCalculator::COST_PER_MILLION_USD.fetch(model, Ai::PricingCalculator::COST_PER_MILLION_USD['claude-sonnet-4-5'])
    ((input_tokens * rates[:input]) + (output_tokens * rates[:output])) / 1_000_000.0
  end
end
