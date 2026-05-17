# Thin wrapper around the Anthropic Messages API. Uses HTTParty directly so we
# don't depend on any gem version. Designed to log every invocation through the
# Ai::Invocation model for cost tracking.
class Ai::ClaudeService
  class Error < StandardError; end

  API_BASE = 'https://api.anthropic.com'
  API_VERSION = '2023-06-01'

  COST_PER_MILLION = {
    'claude-opus-4-5' => { input: 15.0, output: 75.0 },
    'claude-sonnet-4-5' => { input: 3.0, output: 15.0 },
    'claude-haiku-4-5' => { input: 0.8, output: 4.0 }
  }.freeze

  def initialize(assistant:, account: nil)
    @assistant = assistant
    @account = account || assistant&.account
  end

  def chat(messages:, system: nil, model: nil, max_tokens: nil, temperature: nil, conversation: nil, phase: 'main')
    api_key = @assistant&.resolved_anthropic_key
    raise Error, 'Anthropic API key not configured' if api_key.blank?

    payload = {
      model: model || @assistant&.model || 'claude-sonnet-4-5',
      max_tokens: max_tokens || @assistant&.max_tokens || 1024,
      temperature: temperature || @assistant&.temperature || 0.3,
      system: system,
      messages: messages
    }.compact

    started_at = Time.zone.now
    response = HTTParty.post(
      "#{API_BASE}/v1/messages",
      headers: headers(api_key),
      body: payload.to_json,
      timeout: 30
    )
    track_invocation(response: response, payload: payload, started_at: started_at, conversation: conversation, phase: phase)
  rescue StandardError => e
    Rails.logger.error("[Athenas] Claude chat failed: #{e.message}")
    raise Error, e.message
  end

  private

  def headers(api_key)
    {
      'x-api-key' => api_key,
      'anthropic-version' => API_VERSION,
      'content-type' => 'application/json'
    }
  end

  def track_invocation(response:, payload:, started_at:, conversation:, phase:)
    duration_ms = ((Time.zone.now - started_at) * 1000).to_i
    if !response.success?
      log_failed(payload: payload, response: response, duration_ms: duration_ms, conversation: conversation, phase: phase)
      raise Error, "Claude API #{response.code}: #{response.body.to_s.truncate(400)}"
    end
    parsed = response.parsed_response
    text = extract_text(parsed)
    log_success(payload: payload, parsed: parsed, duration_ms: duration_ms, conversation: conversation, phase: phase)
    {
      content: text,
      model: parsed['model'],
      stop_reason: parsed['stop_reason'],
      raw: parsed
    }
  end

  def extract_text(parsed)
    blocks = parsed['content'] || []
    blocks.filter_map { |b| b['text'] if b['type'] == 'text' }.join
  end

  def log_success(payload:, parsed:, duration_ms:, conversation:, phase:)
    usage = parsed['usage'] || {}
    input_tokens = usage['input_tokens'].to_i
    output_tokens = usage['output_tokens'].to_i
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
  rescue StandardError => e
    Rails.logger.error("[Athenas] invocation logging failed: #{e.message}")
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

  def compute_cost(model, input_tokens, output_tokens)
    rates = COST_PER_MILLION[model] || COST_PER_MILLION['claude-sonnet-4-5']
    (input_tokens * rates[:input] + output_tokens * rates[:output]) / 1_000_000.0
  end
end
