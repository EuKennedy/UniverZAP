# Writes the response-log row for one Claude call.
#
# Split out of Ai::ClaudeService because they answer different questions.
# ClaudeService is an HTTP wrapper: talk to Anthropic, retry the blips, surface
# the text. This decides what a call is worth remembering about, which is a
# product concern that grows every sprint (guardrail flags, prompt versions,
# A/B replay) and has no business making the transport class longer.
#
# `context` is what the caller knew at call time:
#   { conversation:, phase:, log: { user_message:, chunks:, prompt_version:,
#     delivery_status: } }
# `log` is present only for calls that are producing text a person will read.
# Without it the row is pure cost telemetry, which is all a summary or a
# classifier call ever needs to be.
class Ai::InvocationRecorder
  def initialize(assistant:, account:, context:)
    @assistant = assistant
    @account = account
    @context = context
  end

  def success(payload:, usage:, duration_ms:, tokens:, cents_brl:)
    input_tokens, output_tokens = tokens
    Ai::Invocation.create!(
      identity(payload).merge(
        input_tokens: input_tokens, output_tokens: output_tokens,
        cache_read_tokens: usage['cache_read_input_tokens'].to_i,
        cache_write_tokens: usage['cache_creation_input_tokens'].to_i,
        cost_usd: cost_usd(payload[:model], input_tokens, output_tokens),
        cost_brl: cents_brl / 100.0, duration_ms: duration_ms, status: 'success'
      ).merge(response_log(payload))
    )
  end

  # A failed call is still a logged call. When the caller was producing a reply,
  # the row is stamped `failed` so "no response escapes the audit" holds for the
  # ones that never made it out.
  def failure(payload:, response:, duration_ms:)
    Ai::Invocation.create!(
      identity(payload).merge(
        duration_ms: duration_ms, status: 'error',
        error_message: "#{response.code}: #{response.body.to_s.truncate(300)}"
      ).merge(response_log(payload)).merge(log.blank? ? {} : { delivery_status: 'failed' })
    )
  end

  private

  def log
    @log ||= @context[:log] || {}
  end

  def identity(payload)
    conversation = @context[:conversation]
    {
      ai_assistant: @assistant, account: @account,
      conversation_id: conversation&.id, phase: @context[:phase], model: payload[:model],
      # Playground turns are billed like any other call, so they stay in the
      # spend figures; the flag is what keeps them out of the supervision queue.
      sandbox: conversation.respond_to?(:sandbox?) && conversation.sandbox?
    }
  end

  def response_log(payload)
    return {} if log.blank?

    {
      # nil on later iterations of a tool loop: the prompt is byte-identical to
      # the one already stored for this turn (see Ai::Agent::ToolLoopService).
      system_prompt: log[:skip_snapshot] ? nil : clip(payload[:system]),
      user_message: clip(log[:user_message]),
      chunks_used: Array(log[:chunks]),
      prompt_version: log[:prompt_version],
      trigger_message_id: log[:trigger_message_id],
      delivery_status: log[:delivery_status]
    }
  end

  def clip(text)
    text.to_s.presence&.truncate(Ai::Invocation::SNAPSHOT_MAX_CHARS)
  end

  # Pricing lives in Ai::PricingCalculator (single source of truth) so the
  # telemetry recorded here can never drift from what the ledger debits.
  def cost_usd(model, input_tokens, output_tokens)
    rates = Ai::PricingCalculator::COST_PER_MILLION_USD.fetch(
      model, Ai::PricingCalculator::COST_PER_MILLION_USD['claude-sonnet-4-5']
    )
    ((input_tokens * rates[:input]) + (output_tokens * rates[:output])) / 1_000_000.0
  end
end
