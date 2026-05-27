class Ai::QuotaService
  # BRL-credit gate guarding every Claude invocation. Replaces the
  # earlier "N invocations per month" counter: now the operator's
  # remaining balance — denominated in cents of real — decides whether a
  # call goes through. The first time the balance hits zero we grant a
  # one-shot 10% grace top-up so an in-flight conversation never gets
  # decapitated; subsequent exhaustions throw `QuotaExhaustedError` and
  # the controller layer translates that into HTTP 402 for the dashboard
  # paywall modal.
  EXPECTED_INPUT_TOKENS_DEFAULT = 1_500

  def self.check!(account:, model: nil, max_output_tokens: 1_024, expected_input_tokens: EXPECTED_INPUT_TOKENS_DEFAULT)
    new(account: account).check!(
      model: model,
      max_output_tokens: max_output_tokens,
      expected_input_tokens: expected_input_tokens
    )
  end

  def self.usage_summary(account:)
    new(account: account).usage_summary
  end

  def initialize(account:)
    @account = account
    @ledger = Ai::CreditLedger.new(account)
  end

  def check!(model:, max_output_tokens:, expected_input_tokens: EXPECTED_INPUT_TOKENS_DEFAULT)
    estimated_cents = Ai::PricingCalculator.estimated_cost_cents_brl(
      model: model || 'claude-sonnet-4-5',
      max_output_tokens: max_output_tokens,
      expected_input_tokens: expected_input_tokens
    )
    return if @ledger.enough?(estimated_cents)

    # First-time exhaustion: drop the grace credit and let the call
    # proceed so we never amputate a customer-facing reply mid-stream.
    # The flag in `grant_grace!` is single-shot, so subsequent quota
    # misses can't piggyback on it.
    return if @ledger.grant_grace! && @ledger.enough?(estimated_cents)

    Rails.logger.warn(
      "[Athenas] credits exhausted account=#{@account.id} balance_cents=#{@ledger.balance_cents} estimated_cents=#{estimated_cents}"
    )
    raise Ai::CreditLedger::QuotaExhaustedError.new(
      account: @account,
      attempted_cents: estimated_cents,
      balance_cents: @ledger.balance_cents
    )
  end

  def usage_summary
    @ledger.summary
  end
end
