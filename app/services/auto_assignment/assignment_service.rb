class AutoAssignment::AssignmentService
  pattr_initialize [:inbox!]

  def perform_bulk_assignment(limit: 100)
    return 0 unless inbox.auto_assignment_v2_enabled?
    return 0 unless inbox.enable_auto_assignment?

    assigned_count = 0

    unassigned_conversations(limit).each do |conversation|
      assigned_count += 1 if perform_for_conversation(conversation)
    end

    assigned_count
  end

  private

  def perform_for_conversation(conversation)
    return false unless assignable?(conversation)

    agent = find_available_agent(conversation)
    return false unless agent

    assign_conversation(conversation, agent)
  end

  def assignable?(conversation)
    conversation.status == 'open' &&
      conversation.assignee_id.nil?
  end

  def unassigned_conversations(limit)
    scope = inbox.conversations.unassigned.open

    # Apply conversation priority using assignment policy if available
    scope = if policy&.longest_waiting?
              scope.reorder(last_activity_at: :asc, created_at: :asc)
            else
              scope.reorder(created_at: :asc)
            end

    scope.limit(limit)
  end

  def find_available_agent(conversation = nil)
    agents = filter_agents_by_team(candidate_agents, conversation)
    return nil if agents.nil?

    agents = filter_agents_by_rate_limit(agents)
    agents = filter_agents_by_capacity(agents)
    return nil if agents.empty?

    sticky_agent(agents, conversation) || selector.select_agent(agents)
  end

  # Presence is the upstream default; a policy can opt out so a team that
  # answers from the phone without the dashboard open still gets conversations.
  def candidate_agents
    return inbox.available_agents if policy.nil? || policy.require_online?

    inbox.inbox_members.includes(:user)
  end

  def filter_agents_by_capacity(agents)
    capped = agents.select { |member| member.assignment_capacity.present? }
    return agents if capped.empty?

    counts = inbox.conversations.open.where(assignee_id: capped.map(&:user_id)).group(:assignee_id).count
    agents.reject { |member| member.assignment_capacity.present? && counts.fetch(member.user_id, 0) >= member.assignment_capacity }
  end

  # Sticky: the agent who handled the contact's previous conversation keeps
  # the relationship, as long as they are still eligible right now.
  def sticky_agent(agents, conversation)
    return nil unless policy&.sticky_contact? && conversation&.contact_id

    previous_assignee_id = conversation.contact.conversations
                                       .where.not(id: conversation.id).where.not(assignee_id: nil)
                                       .order(created_at: :desc).pick(:assignee_id)
    agents.find { |member| member.user_id == previous_assignee_id }&.user
  end

  def selector
    policy&.least_busy? ? least_busy_selector : round_robin_selector
  end

  def policy
    @policy ||= inbox.assignment_policy
  end

  def filter_agents_by_team(agents, conversation)
    return agents if conversation&.team_id.blank?

    team = conversation.team
    return nil if team.blank? || team.allow_auto_assign.blank?

    team_member_ids = team.members.ids
    agents.where(user_id: team_member_ids)
  end

  def filter_agents_by_rate_limit(agents)
    agents.select do |agent_member|
      rate_limiter = build_rate_limiter(agent_member.user)
      rate_limiter.within_limit?
    end
  end

  def assign_conversation(conversation, agent)
    Current.executed_by = inbox.assignment_policy || inbox
    conversation.update!(assignee: agent)
    Current.executed_by = nil

    rate_limiter = build_rate_limiter(agent)
    rate_limiter.track_assignment(conversation)

    dispatch_assignment_event(conversation, agent)
    true
  ensure
    Current.executed_by = nil
  end

  def dispatch_assignment_event(conversation, agent)
    Rails.configuration.dispatcher.dispatch(
      Events::Types::ASSIGNEE_CHANGED,
      Time.zone.now,
      conversation: conversation,
      user: agent
    )
  end

  def build_rate_limiter(agent)
    AutoAssignment::RateLimiter.new(inbox: inbox, agent: agent)
  end

  def round_robin_selector
    @round_robin_selector ||= AutoAssignment::RoundRobinSelector.new(inbox: inbox)
  end

  def least_busy_selector
    @least_busy_selector ||= AutoAssignment::LeastBusySelector.new(inbox: inbox)
  end
end

AutoAssignment::AssignmentService.prepend_mod_with('AutoAssignment::AssignmentService')
