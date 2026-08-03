# Real performance numbers for ONE agent, straight from the invocation log.
#
# Nothing here is estimated: Ai::Invocation is written on every Claude call with
# the actual tokens, cost, latency and outcome, and Ai::CreditLedgerEntry holds
# the BRL that was actually debited.
#
# IMPORTANT distinction, because conflating the two produces a vanity number:
#   * `calls`   = every Claude call billed to this agent (autopilot turns, but
#                 also operator suggestions, summaries, rewrites, copilot chat,
#                 and each iteration of a tool loop). This is the SPEND figure.
#   * `replies` = messages the customer actually received. This is the WORK
#                 figure, and it is what the UI shows as "Respostas".
class Ai::AnalyticsService
  DEFAULT_DAYS = 30
  MAX_DAYS = 90
  RECENT_REPLIES = 20

  def initialize(assistant:, days: DEFAULT_DAYS)
    @assistant = assistant
    @days = days.to_i.clamp(1, MAX_DAYS)
  end

  def perform
    { period_days: @days, totals: totals, daily: daily, models: models,
      flags: flags, recent_replies: recent_replies }
  end

  private

  def scope
    @scope ||= @assistant.invocations.where(created_at: @days.days.ago..)
  end

  # One call answering a customer can span several invocations (a tool loop),
  # so replies are counted by DISTINCT delivered message, never by call.
  # `live` is belt and braces: a sandbox turn never gets a message_id today, and
  # the day one does it must not inflate the headline "Respostas".
  def replies_scope
    @replies_scope ||= scope.live.where.not(message_id: nil)
  end

  def totals
    build_totals(scope.pick(Arel.sql(TOTALS_SQL)) || [])
  end

  TOTALS_SQL = <<~SQL.squish.freeze
    COUNT(*), COUNT(*) FILTER (WHERE status = 'success'),
    COALESCE(SUM(input_tokens), 0), COALESCE(SUM(output_tokens), 0),
    COALESCE(SUM(cache_read_tokens), 0), COALESCE(SUM(cost_usd), 0),
    COALESCE(AVG(duration_ms), 0),
    COALESCE(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms), 0)
  SQL

  def build_totals(stats)
    calls, ok, input, output, cached, usd, avg_ms, p95_ms = stats
    {
      replies: replies_scope.distinct.count(:message_id),
      calls: calls.to_i, successes: ok.to_i, errors: calls.to_i - ok.to_i,
      success_rate: success_rate(calls.to_i, ok.to_i),
      avg_latency_ms: avg_ms.to_f.round, p95_latency_ms: p95_ms.to_f.round
    }.merge(usage_totals(input, output, cached, usd)).merge(audit_totals)
  end

  # The two numbers the acceptance checklist asks for: how many replies a human
  # should look at, and how many were generated but never reached anybody.
  def audit_totals
    {
      flagged: scope.live.flagged.count,
      undelivered: scope.live.awaiting_delivery.count
    }
  end

  # Distribution of automatic review flags, so the Histórico screen can lead
  # with WHICH problem is recurring instead of a single opaque count.
  def flags
    scope.live.flagged.group(:auto_flag).count
  end

  def success_rate(calls, successes)
    return nil if calls.zero?

    (successes.to_f / calls * 100).round(1)
  end

  def usage_totals(input, output, cached, usd)
    { input_tokens: input.to_i, output_tokens: output.to_i,
      cache_read_tokens: cached.to_i, cost_usd: usd.to_f.round(4),
      cost_cents_brl: spent_cents_brl }
  end

  # The BRL actually debited from the operator's balance, not a conversion of
  # the USD figure. Debits are stored as negative cents, hence the abs.
  def spent_cents_brl
    Ai::CreditLedgerEntry.where(ai_invocation_id: scope.select(:id), kind: 'consumption')
                         .sum(:amount_cents_brl).abs
  end

  # Zero-filled: GROUP BY only emits days that had traffic, so plotting it raw
  # would squeeze a silent week into nothing and make the chart lie about time.
  def daily
    found = scope.group(Arel.sql('DATE(created_at)'))
                 .pluck(Arel.sql('DATE(created_at), COUNT(*), COALESCE(SUM(cost_usd), 0), COALESCE(AVG(duration_ms), 0)'))
                 .index_by { |row| row.first.to_s }
    (0...@days).map { |offset| daily_row(found, (@days - 1 - offset).days.ago.to_date.to_s) }
  end

  def daily_row(found, date)
    row = found[date]
    { date: date, calls: row ? row[1].to_i : 0,
      cost_usd: row ? row[2].to_f.round(4) : 0.0,
      avg_latency_ms: row ? row[3].to_f.round : 0 }
  end

  def models
    scope.group(:model).order(Arel.sql('COUNT(*) DESC'))
         .pluck(Arel.sql('model, COUNT(*), COALESCE(SUM(cost_usd), 0)'))
         .map { |model, count, usd| { model: model, calls: count.to_i, cost_usd: usd.to_f.round(4) } }
  end

  # The actual text the customer received, next to what that reply really cost.
  # Aggregated per message because a tool-using turn bills several calls, and
  # showing only the last one would under-report the price of that answer.
  # Two queries on purpose. Aggregating the text columns over the whole period
  # and only then applying LIMIT 20 makes Postgres build arrays of every reply
  # body in the window just to throw them away; picking the ids first keeps the
  # heavy aggregation to the twenty rows that are actually rendered.
  def recent_replies
    ids = replies_scope.group(:message_id)
                       .reorder(Arel.sql('MAX(created_at) DESC'))
                       .limit(RECENT_REPLIES).pluck(:message_id)
    return [] if ids.empty?

    rows = replies_scope.where(message_id: ids).group(:message_id)
                        .reorder(Arel.sql('MAX(created_at) DESC'))
                        .pluck(Arel.sql(REPLIES_SQL))
    contents = reply_contents(ids)
    rows.map { |row| reply_row(row, contents) }
  end

  # A turn can bill several calls; the LAST one is the generation whose text was
  # delivered, so the review fields are read from it rather than aggregated.
  REPLIES_SQL = <<~SQL.squish.freeze
    message_id, MAX(created_at), SUM(cost_usd), SUM(duration_ms),
    MAX(model), MAX(conversation_id), COUNT(*),
    (array_agg(auto_flag ORDER BY created_at DESC))[1],
    (array_agg(confidence ORDER BY created_at DESC))[1],
    (array_agg(user_message ORDER BY created_at DESC))[1],
    (array_agg(ai_response ORDER BY created_at DESC))[1]
  SQL

  # Scoped to the agent's own account: analytics must never render a message
  # body fetched by raw id.
  def reply_contents(message_ids)
    Message.where(account_id: @assistant.account_id, id: message_ids).pluck(:id, :content).to_h
  end

  # The live message is the source of truth for what was delivered. The logged
  # snapshot is the fallback, so a deleted message leaves a readable audit trail
  # instead of an empty row.
  def reply_row(row, contents)
    message_id, at, usd, ms, model, conversation_id, calls, flag, confidence, asked, answered = row
    { id: message_id, conversation_id: conversation_id, model: model,
      content: contents[message_id].presence || answered.to_s,
      user_message: asked.to_s, created_at: at.to_i,
      cost_usd: usd.to_f.round(4), duration_ms: ms.to_i, calls: calls.to_i,
      auto_flag: flag, confidence: confidence&.to_f }
  end
end
