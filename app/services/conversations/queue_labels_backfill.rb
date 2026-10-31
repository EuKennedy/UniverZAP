# Puts the stage tags of old conversations in line with QueueLabelsService:
#   - answered and still tagged novo-contato/triagem: em-atendimento;
#   - resolved: no stage tag, and no closing tag if it carries an appointment.
# Silent on purpose: taggings and the label cache only, so no activity note, no
# automation and no event for a change in history. Counts without `apply`.
class Conversations::QueueLabelsBackfill
  ENTRY_STAGES = Conversations::QueueLabelsService::ENTRY_STAGES
  ACTIVE_STAGE = Conversations::QueueLabelsService::ACTIVE_STAGE

  def initialize(account)
    @account = account
    @closing = account.labels.closing.pluck(:title)
    @schedule_status = VerticalProfile.for(account).schedule_status
  end

  def perform(apply: false)
    return { skipped: true } unless @account.labels.exists?(title: ACTIVE_STAGE)

    counts = Hash.new(0)
    @account.conversations.regular.tagged_with(ENTRY_STAGES + [ACTIVE_STAGE] + @closing, any: true, on: :labels).find_each do |conversation|
      current = conversation.label_list.to_a
      following = next_labels(conversation, current)
      next if following.sort == current.sort

      counts[conversation.status] += 1
      write(conversation, following) if apply
    end
    counts
  end

  private

  def next_labels(conversation, current)
    return ended_labels(current) if conversation.resolved?
    return current unless conversation.first_reply_created_at && current.intersect?(ENTRY_STAGES)

    (current - ENTRY_STAGES) | [ACTIVE_STAGE]
  end

  def ended_labels(current)
    kept = current - ENTRY_STAGES - [ACTIVE_STAGE]
    current.include?(@schedule_status) ? kept - @closing : kept
  end

  def write(conversation, labels)
    conversation.set_tag_list_on(:labels, labels)
    conversation.save_tags
    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_column(:cached_label_list, labels.join("#{ActsAsTaggableOn.delimiter} "))
    # rubocop:enable Rails/SkipsModelValidations
  end
end
