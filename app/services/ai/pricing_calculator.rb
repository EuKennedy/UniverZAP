class Ai::PricingCalculator
  # Anthropic 2025 list prices, USD per million tokens. We mirror the same
  # table the ClaudeService uses internally for token counting; keeping a
  # single source of truth would be nice once the OSS upstream stabilises
  # but for now it's two short hashes that rarely change.
  COST_PER_MILLION_USD = {
    'claude-opus-4-5'   => { input: 15.0, output: 75.0 },
    'claude-sonnet-4-5' => { input: 3.0,  output: 15.0 },
    'claude-haiku-4-5'  => { input: 0.8,  output: 4.0 }
  }.freeze

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

  def self.cost_cents_brl(model:, input_tokens:, output_tokens:, markup: DEFAULT_MARKUP)
    new(markup: markup).cost_cents_brl(model: model, input_tokens: input_tokens, output_tokens: output_tokens)
  end

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

  def cost_cents_brl(model:, input_tokens:, output_tokens:)
    rates = COST_PER_MILLION_USD.fetch(model, COST_PER_MILLION_USD['claude-sonnet-4-5'])
    usd  = ((input_tokens * rates[:input]) + (output_tokens * rates[:output])) / 1_000_000.0
    brl  = usd * @rate * @markup
    (brl * CENTS_PER_REAL).round
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
