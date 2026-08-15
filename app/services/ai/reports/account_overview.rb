# The whole account's agents, in one payload.
#
# Everything measurable about the AI module already existed and all of it was
# per agent, inside one agent's edit screen. An operator with three agents had
# three places to look and no way to ask the only question that matters when
# there is more than one: which of them is worth the money.
#
# Composed rather than written as one query, because the four families come off
# four different tables at four different grains — the call log, the human
# verdicts, the commercial ledgers and the credit ledger. Each part answers for
# its own table and hands back the same two shapes, totals and by-agent, so this
# class only has to merge and derive.
class Ai::Reports::AccountOverview
  DEFAULT_DAYS = 30
  ALLOWED_DAYS = [7, 30, 90].freeze
  # Average time a human takes to read and answer one message. The single
  # assumption in this payload, returned beside the number it produces so
  # nobody quotes the hours without it. Same figure Ai::RoiService uses; they
  # must never drift, or the account panel and the agent panel will disagree
  # about the same month.
  SECONDS_PER_HUMAN_REPLY = Ai::RoiService::SECONDS_PER_HUMAN_REPLY

  def initialize(account:, days: DEFAULT_DAYS)
    @account = account
    # Snapped to the periods the screen offers rather than clamped to a range.
    # A free-form `days` would let one person quote 43 days and another 30 and
    # call both "the month".
    @days = ALLOWED_DAYS.include?(days.to_i) ? days.to_i : DEFAULT_DAYS
  end

  def perform
    {
      period_days: @days,
      timezone: clock.tz_name,
      generated_at: Time.current.to_i,
      totals: totals,
      daily: daily,
      hourly: invocations.hourly,
      models: invocations.models,
      phases: invocations.phases,
      flags: invocations.flags,
      quality: quality.totals,
      leads: commercial.leads,
      revenue: commercial.revenue,
      bookings: commercial.bookings,
      credits: credits.totals,
      agents: agents
    }
  end

  private

  def clock
    @clock ||= Ai::Reports::AccountClock.new(@account)
  end

  def invocations
    @invocations ||= Ai::Reports::InvocationMetrics.new(account: @account, days: @days, zone: clock.zone)
  end

  def quality
    @quality ||= Ai::Reports::QualityMetrics.new(account: @account, days: @days)
  end

  def commercial
    @commercial ||= Ai::Reports::CommercialMetrics.new(account: @account, days: @days, zone: clock.zone)
  end

  def credits
    @credits ||= Ai::Reports::CreditMetrics.new(account: @account, days: @days, zone: clock.zone)
  end

  # The call log owns the shape of the series, including which days are silent;
  # the ledger only says what each of those days cost. Zipping here rather than
  # joining in SQL keeps a day with spend but no calls from vanishing, and a day
  # with calls but no debit from disappearing off the chart.
  def daily
    spend = credits.daily_consumption
    invocations.daily.map { |row| row.merge(cost_cents_brl: spend[row[:date]].to_i) }
  end

  def totals
    spent = credits.totals[:consumed_cents_brl]
    invocations.totals.merge(
      cost_cents_brl: spent,
      hours_saved: hours_saved(invocations.totals[:replies]),
      hours_saved_assumption_seconds: SECONDS_PER_HUMAN_REPLY,
      cache_savings_ratio: cache_ratio(invocations.totals)
    ).merge(unit_economics(spent, invocations.totals))
  end

  # The numbers an operator repeats to somebody else. Each one is NULL rather
  # than zero when its denominator is silent: "R$ 0,00 por agendamento" reads
  # like the agent books for free, when it means nobody booked.
  def unit_economics(spent, stats)
    revenue_brl = commercial.revenue[:total_brl]
    {
      cost_per_reply_brl: per(spent, stats[:replies]),
      cost_per_conversation_brl: per(spent, stats[:conversations]),
      cost_per_booking_brl: per(spent, commercial.bookings[:booked]),
      revenue_brl: revenue_brl,
      roi: roi(spent, revenue_brl)
    }
  end

  # A row per agent, every column meaning exactly what the same column means in
  # the summary above. Sorted by the work figure, so the agent carrying the
  # account is the first line and not an alphabetical accident.
  def agents
    log = invocations.by_agent
    @account.ai_assistants.order(:name).map { |assistant| agent_row(assistant, log[assistant.id] || {}) }
            # Name breaks the tie, so two idle agents do not swap places between
            # one refresh and the next: sort_by is not stable, and a table that
            # reshuffles under the reader is a table nobody trusts.
            .sort_by { |row| [-row[:replies].to_i, row[:name].to_s] }
  end

  def agent_row(assistant, stats)
    spent = credits.by_agent[assistant.id].to_i
    stats.merge(
      id: assistant.id, name: assistant.name, active: assistant.active,
      # So the screen can print "—" instead of "0" for an agent whose agenda we
      # do not hold: belezaki books on the salon's own system and leaves no row
      # in our table, and a zero there reads as a failure to book.
      agenda_provider: assistant.agenda_provider,
      cost_cents_brl: spent,
      cost_per_reply_brl: per(spent, stats[:replies]),
      feedback: quality.by_agent[assistant.id] || { 'up' => 0, 'down' => 0, 'ideal' => 0 },
      flags: invocations.flags_by_agent[assistant.id] || {}
    ).merge(commercial_row(assistant, spent))
  end

  def commercial_row(assistant, spent)
    row = commercial.by_agent[assistant.id] || {}
    row.merge(roi: roi(spent, row[:revenue_brl].to_f))
  end

  def hours_saved(replies)
    ((replies.to_i * SECONDS_PER_HUMAN_REPLY) / 3600.0).round(1)
  end

  # How much of the input never had to be paid for at full price. The agent's
  # prompt is cached and re-read on every turn, so this is the difference
  # between the module being viable and not.
  def cache_ratio(stats)
    billed = stats[:input_tokens].to_i + stats[:cache_read_tokens].to_i
    return nil if billed.zero?

    (stats[:cache_read_tokens].to_f / billed * 100).round(1)
  end

  def per(cents, count)
    return nil if count.to_i.zero?

    (cents.to_f / 100 / count).round(2)
  end

  # NULL until there is spend to divide by. Revenue with no cost is not an
  # infinite return, it is a month nobody has been billed for yet.
  def roi(cents, revenue_brl)
    return nil if cents.to_i.zero?

    (revenue_brl.to_f / (cents.to_f / 100)).round(2)
  end
end
