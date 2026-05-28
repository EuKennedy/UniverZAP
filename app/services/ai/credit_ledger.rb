class Ai::CreditLedger
  # Soft-warning thresholds. Anything <= 5% of the remaining starter
  # credits is `:exhausted`; the rest of the gradient mirrors the
  # operator-facing banner colour scheme (yellow at 80%, orange at 95%).
  THRESHOLD_WARN_80 = 0.20
  THRESHOLD_WARN_95 = 0.05

  # +10% grace credit. Granted the first time an account would otherwise
  # be blocked mid-conversation, then the flag flips so future
  # exhaustions hard-stop the flow.
  GRACE_MULTIPLIER = 0.10

  class QuotaExhaustedError < StandardError
    # `reason` lets the dashboard pick the right paywall copy:
    #   'balance'    → "Seus créditos acabaram, recarregue"
    #   'daily_cap'  → "Limite diário atingido, tente amanhã ou aumente o teto"
    def initialize(account:, attempted_cents:, balance_cents:, reason: 'balance')
      @account = account
      @attempted_cents = attempted_cents
      @balance_cents = balance_cents
      @reason = reason
      super("Athenas quota exhausted (reason=#{reason}) for account #{account.id}: " \
            "needed #{attempted_cents} cents, balance #{balance_cents} cents")
    end

    attr_reader :account, :attempted_cents, :balance_cents, :reason
  end

  attr_reader :account

  def initialize(account)
    @account = account
  end

  def balance_cents
    account.token_credit_balance_cents_brl.to_i
  end

  def lifetime_purchased_cents
    account.token_credit_lifetime_purchased_cents_brl.to_i
  end

  # Total credits ever granted/purchased — the denominator we use for the
  # "you've used 80% of your starter pack" copy on the banner.
  def lifetime_granted_cents
    @lifetime_granted_cents ||= account.ai_credit_ledger_entries.credits.sum(:amount_cents_brl)
  end

  def enough?(cents_brl)
    balance_cents >= cents_brl.to_i
  end

  # Returns one of :ok / :warn_80 / :warn_95 / :exhausted so the UI can
  # render the right banner colour without recomputing percentages.
  def threshold_status
    base = lifetime_granted_cents.to_i
    return :ok if base.zero?
    return :exhausted if balance_cents <= 0

    ratio = balance_cents.to_f / base
    return :warn_95 if ratio <= THRESHOLD_WARN_95
    return :warn_80 if ratio <= THRESHOLD_WARN_80

    :ok
  end

  # Average consumption (cents of real) per day across the trailing 7
  # days. Drives the "X days remaining at current pace" copy on the
  # modal and the auto-recharge nudge.
  def burn_rate_cents_per_day
    seven_days_ago = 7.days.ago
    consumed = account.ai_credit_ledger_entries
                      .consumptions
                      .within(seven_days_ago..Time.current)
                      .sum(:amount_cents_brl).abs
    (consumed / 7.0).round
  end

  def estimated_days_remaining
    rate = burn_rate_cents_per_day
    return Float::INFINITY if rate.zero?

    (balance_cents.to_f / rate).floor
  end

  def debit!(invocation:, cents_brl:, description: nil)
    return if cents_brl.to_i.zero?

    transaction do
      Ai::CreditLedgerEntry.create!(
        account: account,
        kind: 'consumption',
        amount_cents_brl: -cents_brl.to_i,
        ai_invocation: invocation,
        description: description
      )
      account.update_columns( # rubocop:disable Rails/SkipsModelValidations
        token_credit_balance_cents_brl: balance_cents - cents_brl.to_i,
        updated_at: Time.current
      )
    end
  end

  def credit_purchase!(cents_brl:, external_payment_id:, description: nil)
    return false if external_payment_id.present? && already_credited?(external_payment_id)

    transaction do
      Ai::CreditLedgerEntry.create!(
        account: account,
        kind: 'purchase',
        amount_cents_brl: cents_brl.to_i,
        external_payment_id: external_payment_id.presence,
        description: description || 'Athenas credit purchase'
      )
      account.update_columns( # rubocop:disable Rails/SkipsModelValidations
        token_credit_balance_cents_brl: balance_cents + cents_brl.to_i,
        token_credit_lifetime_purchased_cents_brl: lifetime_purchased_cents + cents_brl.to_i,
        updated_at: Time.current
      )
    end
    true
  end

  def grant_grace!
    return false if account.token_credit_grace_used?

    grace_amount = [(lifetime_granted_cents * GRACE_MULTIPLIER).round, 250].max

    transaction do
      Ai::CreditLedgerEntry.create!(
        account: account,
        kind: 'grace',
        amount_cents_brl: grace_amount,
        description: 'One-time grace credit so the first exhaustion never cuts an in-flight conversation'
      )
      account.update_columns( # rubocop:disable Rails/SkipsModelValidations
        token_credit_balance_cents_brl: balance_cents + grace_amount,
        token_credit_grace_used: true,
        updated_at: Time.current
      )
    end
    true
  end

  def recent_entries(limit: 20)
    account.ai_credit_ledger_entries.recent.limit(limit)
  end

  def summary
    {
      balance_cents_brl: balance_cents,
      lifetime_granted_cents_brl: lifetime_granted_cents,
      lifetime_purchased_cents_brl: lifetime_purchased_cents,
      grace_used: account.token_credit_grace_used?,
      threshold_status: threshold_status,
      burn_rate_cents_per_day: burn_rate_cents_per_day,
      estimated_days_remaining: estimated_days_remaining_for_payload
    }
  end

  private

  def estimated_days_remaining_for_payload
    days = estimated_days_remaining
    days.infinite? ? nil : days
  end

  def already_credited?(external_payment_id)
    Ai::CreditLedgerEntry.exists?(external_payment_id: external_payment_id)
  end

  def transaction(&)
    ActiveRecord::Base.transaction(&)
  end
end
