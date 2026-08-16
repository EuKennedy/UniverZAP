# The money, as the operator's balance actually saw it.
#
# Deliberately NOT a conversion of the USD figure in ai_invocations. That number
# is what Anthropic charged us; this one is what came off the customer's
# balance, and the two differ by the margin. Quoting the first to an operator
# tells them a price nobody charged them.
#
# Debits are stored as negative cents, so every figure here is absolute and the
# sign is carried by the name.
class Ai::Reports::CreditMetrics
  def initialize(account:, period:, zone: Time.zone)
    @account = account
    @period = period
    @zone = zone
  end

  # Memoized, like every public reader here: the orchestrator reads totals for
  # the summary and again to divide by, and by_agent once per row of the
  # comparison table. Unmemoized, a fixed set of queries becomes one per agent.
  def totals
    @totals ||= build_totals
  end

  def by_agent
    @by_agent ||= build_by_agent
  end

  # Keyed by local date, for the caller to zip into its own zero-filled series.
  # In BRL and not a conversion of the USD in the call log, so the spend chart
  # and the spend tile above it cannot disagree about the same day.
  def daily_consumption
    @daily_consumption ||= entries.consumptions.group(Arel.sql(local_date))
                                  .sum(:amount_cents_brl)
                                  .to_h { |date, cents| [date.to_s, cents.abs] }
  end

  private

  def build_totals
    consumed = entries.consumptions.sum(:amount_cents_brl).abs
    {
      balance_cents_brl: @account.token_credit_balance_cents_brl.to_i,
      consumed_cents_brl: consumed,
      purchased_cents_brl: entries.purchases.sum(:amount_cents_brl),
      granted_cents_brl: entries.where(kind: %w[grant grace]).sum(:amount_cents_brl),
      refunded_cents_brl: entries.where(kind: 'refund').sum(:amount_cents_brl),
      # How many more days the balance lasts at the pace of this period. NULL
      # when nothing was spent, because dividing by a silent month produces an
      # infinity the screen would have to special-case anyway.
      days_of_balance_left: runway(consumed)
    }
  end

  # Joined through the invocation, because a ledger entry knows the account it
  # billed and not the agent that caused it. Entries whose invocation was
  # nullified by an agent being deleted drop out here, which is correct: the
  # spend still counts for the account and can no longer be attributed.
  def build_by_agent
    Ai::CreditLedgerEntry.consumptions
                         .where(account_id: @account.id, created_at: @period.range)
                         .joins('INNER JOIN ai_invocations ON ai_invocations.id = ai_credit_ledger_entries.ai_invocation_id')
                         .group('ai_invocations.ai_assistant_id')
                         .sum(:amount_cents_brl)
                         .transform_values(&:abs)
  end

  def local_date
    quoted = ActiveRecord::Base.connection.quote(@zone.tzinfo.name)
    "DATE(ai_credit_ledger_entries.created_at AT TIME ZONE 'UTC' AT TIME ZONE #{quoted})"
  end

  def entries
    @entries ||= Ai::CreditLedgerEntry.where(account_id: @account.id, created_at: @period.range)
  end

  def runway(consumed)
    return nil if consumed.zero?

    (@account.token_credit_balance_cents_brl.to_i / (consumed.to_f / @period.days)).floor
  end
end
