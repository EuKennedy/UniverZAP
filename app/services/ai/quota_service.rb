class Ai::QuotaService
  # BRL-credit gate guarding every Claude invocation. Two layers:
  #
  # 1. Daily USD cap (account-scoped, env-defaulted). Stops a runaway
  #    autopilot loop or an abusive tenant from racking up a Claude bill
  #    we have to absorb. The cap is checked AGAINST the actual `cost_usd`
  #    column on `ai_invocations` so it tracks what Anthropic billed us,
  #    not the BRL retail price.
  # 2. BRL credit ledger — the operator's remaining starter / purchased
  #    balance. The first time it hits zero we grant a one-shot 10%
  #    grace top-up so an in-flight conversation never gets decapitated;
  #    subsequent exhaustions throw `QuotaExhaustedError` and the
  #    controller layer translates that into HTTP 402 for the dashboard
  #    paywall modal.
  EXPECTED_INPUT_TOKENS_DEFAULT = 1_500
  DEFAULT_DAILY_USD_CAP = 50.0

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
    enforce_daily_cap!

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
      balance_cents: @ledger.balance_cents,
      reason: 'balance'
    )
  end

  def usage_summary
    @ledger.summary.merge(
      daily_usd_cap: account_daily_cap_usd,
      daily_usd_spent: today_usd_spent
    )
  end

  private

  def enforce_daily_cap!
    cap_usd = account_daily_cap_usd
    return if cap_usd.nil? || cap_usd <= 0

    spent_today = today_usd_spent
    return if spent_today < cap_usd

    Rails.logger.warn(
      "[Athenas] daily USD cap hit account=#{@account.id} spent=#{spent_today.round(4)} cap=#{cap_usd}"
    )
    raise Ai::CreditLedger::QuotaExhaustedError.new(
      account: @account,
      attempted_cents: 0,
      balance_cents: @ledger.balance_cents,
      reason: 'daily_cap'
    )
  end

  def account_daily_cap_usd
    override = @account.custom_attributes&.dig('athenas_daily_usd_cap')
    return override.to_f if override.present?

    ENV.fetch('ATHENAS_DAILY_USD_CAP', DEFAULT_DAILY_USD_CAP).to_f
  end

  def today_usd_spent
    @account.ai_invocations
            .where(created_at: Time.current.beginning_of_day..)
            .sum(:cost_usd)
            .to_f
  end
end
