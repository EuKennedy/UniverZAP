# "Agendar" from the customer sheet: writes the appointment onto the
# conversation, makes `agendado` its stage (the vertical's other open
# stages go away; everything else stays) and, when the conversation
# already sits on a Kanban board with a column named "Agendado", moves
# the card there. Never creates a card.
class Conversations::ScheduleService
  LABEL = 'agendado'.freeze
  ATTRIBUTE_KEYS = %w[servico profissional data_agendamento ciclo_recompra_semanas].freeze

  def initialize(conversation:, attributes:)
    @conversation = conversation
    @attributes = attributes.to_h.stringify_keys
  end

  def perform
    @conversation.update!(custom_attributes: merged_attributes, label_list: next_labels)
    Kanban::AutomationService.handle_stage_label_applied(@conversation, LABEL)
    @conversation
  end

  private

  def merged_attributes
    @conversation.custom_attributes.merge(@attributes.slice(*ATTRIBUTE_KEYS).compact_blank)
  end

  def next_labels
    (@conversation.label_list.to_a - open_stage_titles) | [LABEL]
  end

  def open_stage_titles
    vertical = Vertical.find_by(key: @conversation.account.custom_attributes['vertical_template'])
    return [] if vertical.blank?

    vertical.vertical_statuses.where(closes_conversation: false).pluck(:title)
  end
end
