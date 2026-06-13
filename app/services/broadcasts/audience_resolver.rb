# Resolves a broadcast's audience JSON into a de-duplicated list of contact ids.
# Each filter is optional; the final audience is the UNION of every filter that
# is present. Only contacts with a phone number are eligible (WAHA send mode).
class Broadcasts::AudienceResolver
  def initialize(broadcast)
    @broadcast = broadcast
    @account = broadcast.account
    @filters = broadcast.audience_filters
  end

  def contact_ids
    ids = from_contact_labels +
          from_conversation_labels +
          from_funnel_stages +
          from_manual_ids +
          from_phone_numbers

    with_phone(ids.uniq)
  end

  private

  def from_contact_labels
    ids = Array(@filters['contact_label_ids']).map(&:to_i).reject(&:zero?)
    return [] if ids.empty?

    titles = @account.labels.where(id: ids).pluck(:title)
    return [] if titles.empty?

    @account.contacts.tagged_with(titles, any: true).pluck(:id)
  end

  def from_conversation_labels
    ids = Array(@filters['conversation_label_ids']).map(&:to_i).reject(&:zero?)
    return [] if ids.empty?

    titles = @account.labels.where(id: ids).pluck(:title)
    return [] if titles.empty?

    @account.conversations.tagged_with(titles, any: true).pluck(:contact_id)
  end

  def from_funnel_stages
    ids = Array(@filters['funnel_stage_ids']).map(&:to_i).reject(&:zero?)
    return [] if ids.empty?

    task_ids = @account.kanban_tasks.where(funnel_stage_id: ids).select(:id)
    Conversation.joins(:kanban_task_conversations)
                .where(kanban_task_conversations: { kanban_task_id: task_ids })
                .pluck(:contact_id)
  end

  def from_manual_ids
    Array(@filters['contact_ids']).map(&:to_i).reject(&:zero?)
  end

  def from_phone_numbers
    numbers = Array(@filters['phone_numbers']).map { |n| n.to_s.strip }.reject(&:blank?)
    return [] if numbers.empty?

    @account.contacts.where(phone_number: numbers).pluck(:id)
  end

  def with_phone(ids)
    return [] if ids.empty?

    @account.contacts.where(id: ids).where.not(phone_number: [nil, '']).pluck(:id)
  end
end
