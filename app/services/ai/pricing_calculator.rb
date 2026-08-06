class Ai::PricingCalculator
  # Anthropic 2025 list prices, USD per million tokens. Single source of
  # truth: Ai::ClaudeService reads this table for telemetry, the ledger
  # debits through it, so a price update lands everywhere at once.
  COST_PER_MILLION_USD = {
    'claude-opus-4-5' => { input: 15.0, output: 75.0 },
    'claude-sonnet-4-5' => { input: 3.0, output: 15.0 },
    'claude-haiku-4-5' => { input: 0.8, output: 4.0 }
  }.freeze

  # Speech-to-text is billed per MINUTE OF AUDIO, not per token, so it needs
  # its own table. Mixing it into the token table would force every caller to
  # know which unit a given model speaks.
  #
  # Read off elevenlabs.io/pricing/api on 2026-08-04: Scribe v2 is $0.22 per
  # HOUR. The surcharge features (entity detection, redaction, keyterms) are
  # deliberately not used, so the base rate is the whole rate.
  COST_PER_AUDIO_MINUTE_USD = {
    'scribe_v2' => 0.22 / 60.0
  }.freeze

  # Prompt-caching multipliers on the INPUT rate, per Anthropic's pricing:
  # writing a cache entry costs 25% more than a normal input token, reading one
  # back costs a tenth. The whole point of caching is that the operator is
  # charged the cheap rate, so these are applied to the ledger, not just to
  # telemetry.
  CACHE_WRITE_MULTIPLIER = 1.25
  CACHE_READ_MULTIPLIER = 0.1

  # Markup applied on top of the Anthropic invoice. 2x is generous enough
  # to absorb the dollar swings while keeping the per-conversation
  # price under R$1 on Sonnet, which is the psychological threshold the
  # commercial team set.
  DEFAULT_MARKUP = 2.0

  # Hardcoded today; the moment we have automated FX or a billing
  # contract the value moves to credentials/ENV without touching call
  # sites — every consumer talks in cents-of-real already.
  USD_TO_BRL_RATE = 5.0

  CENTS_PER_REAL = 100

  # rubocop:disable Metrics/ParameterLists
  def self.cost_cents_brl(model:, input_tokens:, output_tokens:, cache_write_tokens: 0, cache_read_tokens: 0,
                          markup: DEFAULT_MARKUP)
    new(markup: markup).cost_cents_brl(
      model: model, input_tokens: input_tokens, output_tokens: output_tokens,
      cache_write_tokens: cache_write_tokens, cache_read_tokens: cache_read_tokens
    )
  end
  # rubocop:enable Metrics/ParameterLists

  # Pessimistic upper-bound for the *pre-call* quota check. We don't yet
  # know how many output tokens Claude will emit, so we charge against the
  # configured `max_tokens` ceiling. Cheap to call, easy to reverse:
  # the real consumption is debited inside the post-call hook with the
  # actual token usage.
  def self.estimated_cost_cents_brl(model:, max_output_tokens:, expected_input_tokens: 2_000, markup: DEFAULT_MARKUP)
    new(markup: markup).cost_cents_brl(
      model: model,
      input_tokens: expected_input_tokens,
      output_tokens: max_output_tokens
    )
  end

  def initialize(markup: DEFAULT_MARKUP, rate: USD_TO_BRL_RATE)
    @markup = markup
    @rate = rate
  end

  # Cached tokens are reported by Anthropic OUTSIDE `input_tokens`, so they are
  # billed as their own terms rather than folded into it.
  def cost_cents_brl(model:, input_tokens:, output_tokens:, cache_write_tokens: 0, cache_read_tokens: 0)
    rates = COST_PER_MILLION_USD.fetch(model, COST_PER_MILLION_USD['claude-sonnet-4-5'])
    input_usd = (input_tokens * rates[:input]) +
                (cache_write_tokens.to_i * rates[:input] * CACHE_WRITE_MULTIPLIER) +
                (cache_read_tokens.to_i * rates[:input] * CACHE_READ_MULTIPLIER)
    usd = (input_usd + (output_tokens * rates[:output])) / 1_000_000.0
    brl = usd * @rate * @markup
    (brl * CENTS_PER_REAL).round
  end

  # Transcription cost. Rounded UP to the whole second before pricing: vendors
  # bill partial minutes, and rounding down would hand every voice note a free
  # fraction that only shows up as a shortfall at the end of the month.
  def self.transcription_cost_cents_brl(model:, duration_seconds:, markup: DEFAULT_MARKUP)
    new(markup: markup).transcription_cost_cents_brl(model: model, duration_seconds: duration_seconds)
  end

  def transcription_cost_cents_brl(model:, duration_seconds:)
    per_minute = COST_PER_AUDIO_MINUTE_USD.fetch(model, COST_PER_AUDIO_MINUTE_USD['scribe_v2'])
    usd = (duration_seconds.to_f.ceil / 60.0) * per_minute
    (usd * @rate * @markup * CENTS_PER_REAL).round
  end

  # Inverse helper — used by the purchase modal to translate a BRL
  # package back into a "you'll get X conversations" range. Returns the
  # mid-point estimate (10-turn conversation with mixed model usage).
  def self.estimated_conversations(cents_brl, model: 'claude-sonnet-4-5')
    per_turn = cost_cents_brl(
      model: model,
      input_tokens: 500,
      output_tokens: 300
    )
    return 0 if per_turn.zero?

    # 10 turns per conversation is the median we've seen in the Lizzon
    # historical data. Tune later as we collect more telemetry.
    (cents_brl / (per_turn * 10.0)).floor
  end
end
