class AutoAssignment::InboxRoundRobinService
  pattr_initialize [:inbox!]

  # called on inbox delete
  def clear_queue
    ::Redis::Alfred.delete(round_robin_key)
  end

  # called on inbox member create
  def add_agent_to_queue(user_id)
    ::Redis::Alfred.lpush(round_robin_key, user_id)
  end

  # called on inbox member delete
  def remove_agent_from_queue(user_id)
    ::Redis::Alfred.lrem(round_robin_key, user_id)
  end

  def reset_queue
    clear_queue
    # Read from the database, not from `inbox.inbox_members`: that association
    # may already be loaded — and empty — on this same Inbox object (creating a
    # conversation loads it through the assignment hooks), and the queue would
    # be rebuilt from a stale list. The guard is a separate problem: LPUSH with
    # no values is a Redis error, not a no-op, so an empty inbox must not push.
    member_ids = InboxMember.where(inbox_id: inbox.id).pluck(:user_id)
    add_agent_to_queue(member_ids) if member_ids.any?
  end

  # end of queue management functions

  # allowed member ids = [assignable online agents supplied by the assignment service]
  # the values of allowed member ids should be in string format
  def available_agent(allowed_agent_ids: [])
    reset_queue unless validate_queue?
    user_id = get_member_from_allowed_agent_ids(allowed_agent_ids)
    inbox.inbox_members.find_by(user_id: user_id)&.user if user_id.present?
  end

  private

  def get_member_from_allowed_agent_ids(allowed_agent_ids)
    return nil if allowed_agent_ids.blank?

    user_id = queue.intersection(allowed_agent_ids).pop
    pop_push_to_queue(user_id)
    user_id
  end

  def pop_push_to_queue(user_id)
    return if user_id.blank?

    remove_agent_from_queue(user_id)
    add_agent_to_queue(user_id)
  end

  def validate_queue?
    return true if inbox.inbox_members.map(&:user_id).sort == queue.map(&:to_i).sort
  end

  def queue
    ::Redis::Alfred.lrange(round_robin_key)
  end

  def round_robin_key
    format(::Redis::Alfred::ROUND_ROBIN_AGENTS, inbox_id: inbox.id)
  end
end
