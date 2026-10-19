# Picks the inbox member carrying the fewest open conversations in this inbox.
# Ties go through the inbox round robin so equally loaded agents still rotate.
class AutoAssignment::LeastBusySelector
  pattr_initialize [:inbox!]

  def select_agent(available_agents)
    return nil if available_agents.empty?

    counts = open_counts(available_agents)
    lightest = available_agents.map { |member| counts[member.user_id] }.min
    candidates = available_agents.select { |member| counts[member.user_id] == lightest }

    AutoAssignment::RoundRobinSelector.new(inbox: inbox).select_agent(candidates)
  end

  private

  def open_counts(members)
    Hash.new(0).merge(
      inbox.conversations.open.where(assignee_id: members.map(&:user_id)).group(:assignee_id).count
    )
  end
end
