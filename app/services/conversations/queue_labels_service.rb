# UniverZAP: the stage tags follow what happens in the conversation, so the bar
# of labels always matches the queues. Accounts without the `em-atendimento`
# label (verticals that don't use this flow) are left alone.
#   - the team replied: novo-contato/triagem become em-atendimento;
#   - the conversation ended: none of the three stays on it;
#   - the contact came back: em-atendimento.
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

    apply(labels - ENTRY_STAGES - [ACTIVE_STAGE])
  end

  def reopened
    return unless applicable?

    apply((labels - ENTRY_STAGES) | [ACTIVE_STAGE])
  end

  private

  def labels
    @conversation.label_list.to_a
  end

  def applicable?
    !group_chat? && @conversation.account.labels.exists?(title: ACTIVE_STAGE)
  end

  def group_chat?
    @conversation.is_group || @conversation.is_status_broadcast || @conversation.is_team
  end

  def apply(next_labels)
    @conversation.update_labels(next_labels) if next_labels.sort != labels.sort
  end
end
