# Everything the account panel reads out of ai_invocations.
#
# One query per QUESTION, never one per agent. An account with a dozen agents
# asks Postgres the same number of times as an account with one, because every
# figure here is a GROUP BY on an index that already exists.
#
# The distinction that keeps the panel honest, carried over from
# Ai::AnalyticsService and worth repeating because conflating the two produces a
# vanity number:
#   * calls   = every Claude call billed to the agent, including each iteration
#               of a tool loop, summaries, rewrites and operator suggestions.
#               This is the SPEND figure.
#   * replies = distinct messages a customer actually received. This is the WORK
#               figure, and it is the one a headline may use.
class Ai::Reports::InvocationMetrics
  # Per agent and in total, from the same expression list, so a column can never
  # mean one thing in the summary and another in the table below it.
  #
  # `sandbox` is excluded from the work and supervision counts but NOT from
  # spend: a playground turn costs real money, and hiding it would understate
  # the bill. It is excluded from review counts because nobody needs to audit an
  # answer given to a fake customer.
  STATS_SQL = <<~SQL.squish.freeze
    COUNT(*),
    COUNT(*) FILTER (WHERE status = 'success'),
    COUNT(DISTINCT message_id) FILTER (WHERE message_id IS NOT NULL AND sandbox = FALSE),
    COUNT(DISTINCT conversation_id) FILTER (WHERE message_id IS NOT NULL AND sandbox = FALSE),
    COUNT(*) FILTER (WHERE auto_flag IS NOT NULL AND sandbox = FALSE),
    COUNT(*) FILTER (WHERE delivery_status = 'pending' AND sandbox = FALSE),
    COUNT(*) FILTER (WHERE handoff = TRUE AND sandbox = FALSE),
    COALESCE(SUM(input_tokens), 0), COALESCE(SUM(output_tokens), 0),
    COALESCE(SUM(cache_read_tokens), 0), COALESCE(SUM(cache_write_tokens), 0),
    COALESCE(SUM(cost_usd), 0),
    COALESCE(AVG(duration_ms), 0),
    COALESCE(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms), 0),
    AVG(confidence)
  SQL

  DAILY_SQL = <<~SQL.squish.freeze
    COUNT(*),
    COUNT(DISTINCT message_id) FILTER (WHERE message_id IS NOT NULL AND sandbox = FALSE),
    COALESCE(SUM(cost_usd), 0),
    COALESCE(AVG(duration_ms), 0),
    COUNT(*) FILTER (WHERE auto_flag IS NOT NULL AND sandbox = FALSE),
    COUNT(*) FILTER (WHERE status <> 'success')
  SQL

  COLUMNS = %i[
    calls successes replies conversations flagged undelivered handoffs
    input_tokens output_tokens cache_read_tokens cache_write_tokens
    cost_usd avg_latency_ms p95_latency_ms avg_confidence
  ].freeze

  def initialize(account:, days:, zone:)
    @account = account
    @days = days
    @zone = zone
  end

  def totals
    @totals ||= row_to_hash(scope.pick(Arel.sql(STATS_SQL)) || [])
  end

  def by_agent
    @by_agent ||= scope.group(:ai_assistant_id)
                       .pluck(Arel.sql("ai_assistant_id, #{STATS_SQL}"))
                       .to_h { |row| [row.first, row_to_hash(row.drop(1))] }
  end

  # Zero-filled, because GROUP BY only emits days that had traffic and plotting
  # it raw squeezes a silent week into nothing: the chart would show a busy
  # month that never happened.
  def daily
    found = scope.group(Arel.sql(local_date))
                 .pluck(Arel.sql("#{local_date}, #{DAILY_SQL}"))
                 .index_by { |row| row.first.to_s }
    (0...@days).map { |offset| daily_row(found, (@days - 1 - offset).days.ago.in_time_zone(@zone).to_date.to_s) }
  end

  # All 24 hours, always. A gap in this one is information: it is when the
  # business is closed and the agent is the only thing answering.
  def hourly
    found = scope.where.not(message_id: nil).where(sandbox: false)
                 .group(Arel.sql(local_hour))
                 .pluck(Arel.sql("#{local_hour}, COUNT(DISTINCT message_id)"))
                 .to_h { |hour, count| [hour.to_i, count.to_i] }
    (0..23).map { |hour| { hour: hour, replies: found[hour].to_i } }
  end

  def models
    scope.group(:model).order(Arel.sql('COUNT(*) DESC'))
         .pluck(Arel.sql('model, COUNT(*), COALESCE(SUM(cost_usd), 0)'))
         .map { |model, calls, usd| { model: model, calls: calls.to_i, cost_usd: usd.to_f.round(4) } }
  end

  # Which guardrail keeps firing, in total and per agent. A single "12 flagged"
  # tells nobody whether to fix a price list or a prompt.
  def flags
    flagged_scope.group(:auto_flag).count
  end

  # Memoized because the orchestrator asks for it once per row of the comparison
  # table, and an unmemoized reader turns one query into one per agent.
  def flags_by_agent
    @flags_by_agent ||= build_flags_by_agent
  end

  # What the customer asked, per phase, so an account can see that half its
  # spend is summaries rather than answers.
  def phases
    scope.group(:phase).order(Arel.sql('COUNT(*) DESC'))
         .pluck(Arel.sql('phase, COUNT(*), COALESCE(SUM(cost_usd), 0)'))
         .map { |phase, calls, usd| { phase: phase, calls: calls.to_i, cost_usd: usd.to_f.round(4) } }
  end

  private

  def build_flags_by_agent
    counted = flagged_scope.group(:ai_assistant_id, :auto_flag).count
    counted.each_with_object({}) do |((assistant_id, flag), count), out|
      (out[assistant_id] ||= {})[flag] = count
    end
  end

  def scope
    @scope ||= Ai::Invocation.where(account_id: @account.id, created_at: @days.days.ago..)
  end

  def flagged_scope
    @flagged_scope ||= scope.live.flagged
  end

  # Converted in SQL rather than in Ruby, unlike Ai::RevenueEvent#after_hours?,
  # which loads its rows: that table holds sales and this one holds every Claude
  # call ever made, so the same approach would pull a month of the platform's
  # traffic into memory to read an hour off it.
  #
  # The double conversion is what a `timestamp without time zone` holding UTC
  # needs: the first names what is stored, the second says where to read it.
  def local_time
    @local_time ||= "(created_at AT TIME ZONE 'UTC' AT TIME ZONE #{ActiveRecord::Base.connection.quote(@zone.tzinfo.name)})"
  end

  def local_date
    "DATE#{local_time}"
  end

  def local_hour
    "EXTRACT(HOUR FROM #{local_time})"
  end

  # Split three ways along what each group of columns is about, and not because
  # one method would have been long: the three read from the same row and
  # nothing about them is shared, so a single method is just a wide one.
  def row_to_hash(row)
    values = COLUMNS.zip(row).to_h
    work_totals(values).merge(latency_totals(values)).merge(token_totals(values))
  end

  def work_totals(values)
    calls = values[:calls].to_i
    successes = values[:successes].to_i
    {
      calls: calls, successes: successes, errors: calls - successes,
      success_rate: rate(calls, successes),
      replies: values[:replies].to_i, conversations: values[:conversations].to_i,
      flagged: values[:flagged].to_i, undelivered: values[:undelivered].to_i,
      handoffs: values[:handoffs].to_i
    }
  end

  def latency_totals(values)
    {
      avg_latency_ms: values[:avg_latency_ms].to_f.round,
      p95_latency_ms: values[:p95_latency_ms].to_f.round,
      # NULL when no call in the period reported one, which is a different thing
      # from zero confidence and has to stay distinguishable.
      avg_confidence: values[:avg_confidence]&.to_f&.round(3)
    }
  end

  def token_totals(values)
    {
      input_tokens: values[:input_tokens].to_i, output_tokens: values[:output_tokens].to_i,
      cache_read_tokens: values[:cache_read_tokens].to_i,
      cache_write_tokens: values[:cache_write_tokens].to_i,
      cost_usd: values[:cost_usd].to_f.round(4)
    }
  end

  def rate(calls, successes)
    return nil if calls.to_i.zero?

    (successes.to_f / calls * 100).round(1)
  end

  def daily_row(found, date)
    calls, replies, usd, latency, flagged, errors = found[date]&.drop(1)
    { date: date, calls: calls.to_i, replies: replies.to_i,
      cost_usd: usd.to_f.round(4), avg_latency_ms: latency.to_f.round,
      flagged: flagged.to_i, errors: errors.to_i }
  end
end
