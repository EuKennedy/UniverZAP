# UniverZAP: the stage tags follow what happens in the conversation, so the bar
# of labels always matches the queues. Accounts without the `em-atendimento`
# label (verticals that don't use this flow) are left alone.
#   - the team replied: novo-contato/triagem become em-atendimento;
#   - the conversation ended: none of the three stays on it;
#   - the contact came back: em-atendimento.
# An appointment is the outcome of a scheduled conversation, so it never also
# carries a closing label such as atendimento-encerrado. Labels are read fresh:
# an automation may have just written them from another process.
class Conversations::QueueLabelsService
  ENTRY_STAGES = %w[novo-contato triagem].freeze
  ACTIVE_STAGE = 'em-atendimento'.freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def replied
    return unless applicable? && @conversation.open?

    apply((labels - ENTRY_STAGES) | [ACTIVE_STAGE])
  end

  def ended
    return unless applicable?

    current = labels - ENTRY_STAGES - [ACTIVE_STAGE]
    apply(without_closing_if_scheduled(current))
  end

  def reopened
    return unless applicable?

    apply((labels - ENTRY_STAGES) | [ACTIVE_STAGE])
  end

  # The labels that may go on: what an automation asks for, minus a closing
  # label when the conversation carries an appointment.
  def without_closing_if_scheduled(titles)
    return titles unless scheduled?

    titles - @conversation.account.labels.closing.pluck(:title)
  end

  private

  def labels
    @conversation.reload.label_list.to_a
  end

  def scheduled?
    schedule_status = VerticalProfile.for(@conversation.account).schedule_status
    schedule_status.present? && labels.include?(schedule_status)
  end

  def applicable?
    !group_chat? && @conversation.account.labels.exists?(title: ACTIVE_STAGE)
  end

  def group_chat?
    @conversation.is_group || @conversation.is_status_broadcast || @conversation.is_team
  end

  def apply(next_labels)
    @conversation.update_labels(next_labels) if next_labels.sort != @conversation.label_list.to_a.sort
  end
end
