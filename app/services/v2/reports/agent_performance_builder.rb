# Per-agent block of the management dashboard. Period metrics (assigned,
# replied, resolved, converted, median first response) count conversations
# created in the period by their current assignee; waiting and at risk are the
# live queue. Conversations without an assignee get their own row.
class V2::Reports::AgentPerformanceBuilder
  include V2::Reports::DashboardScopes

  pattr_initialize [:account!, :params!]

  GROUP = :assignee_id

  def build
    agent_ids = (names.keys + period.keys + waiting.keys + at_risk.keys).uniq
    agent_ids.map { |agent_id| row(agent_id) }.sort_by { |row| [-row[:assigned], row[:name].to_s] }
  end

  private

  def row(agent_id)
    assigned, replied, resolved, median = period.fetch(agent_id, [0, 0, 0, nil])
    {
      agent_id: agent_id, name: names[agent_id],
      assigned: assigned, replied: replied, resolved: resolved,
      converted: converted&.fetch(agent_id, 0),
      median_first_response_seconds: median&.round,
      waiting: waiting.fetch(agent_id, 0), at_risk: at_risk.fetch(agent_id, 0)
    }
  end

  def names
    @names ||= account.users.pluck(:id, :name).to_h
  end

  # { assignee_id => [assigned, replied, resolved, median_seconds] }
  def period
    @period ||= period_scope.group(GROUP).pluck(GROUP, Arel.sql('COUNT(*)'), REPLIED, RESOLVED, MEDIAN_FIRST_RESPONSE)
                            .to_h { |agent_id, *metrics| [agent_id, metrics] }
  end

  def converted
    return @converted if defined?(@converted)

    @converted = converted_by(period_scope, GROUP)
  end

  def waiting
    @waiting ||= waiting_scope.group(GROUP).count
  end

  def at_risk
    @at_risk ||= at_risk_scope.group(GROUP).count
  end
end
