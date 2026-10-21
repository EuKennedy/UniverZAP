# "Agendar" from the customer sheet: writes the appointment onto the
# conversation, makes the vertical's scheduling status (`agendado` for salons
# and clinics, see VerticalProfile) its stage — the vertical's other open
# stages go away, everything else stays — and, when the conversation already
# sits on a Kanban board with a column of that name, moves the card there.
# Never creates a card. Only for verticals that schedule (the controller
# refuses the others).
#
# With `resolve: true` ("Resolver > Agendado" in the header) the conversation
# is also resolved in the same save: the customer was won, so the appointment
# status is the closing reason and the panel counts it as a conversion. The
# account's label record is guaranteed so the panel's conversion filter sees it.
class Conversations::ScheduleService
  ATTRIBUTE_KEYS = %w[servico profissional data_agendamento ciclo_recompra_semanas].freeze

  def initialize(conversation:, attributes:, resolve: false)
    @conversation = conversation
    @attributes = attributes.to_h.stringify_keys
    @resolve = resolve
  end

  def perform
    @conversation.account.labels.find_or_create_by!(title: profile.schedule_status)
    changes = { custom_attributes: merged_attributes, label_list: next_labels }
    changes[:status] = :resolved if @resolve
    @conversation.update!(changes)
    Kanban::AutomationService.handle_stage_label_applied(@conversation, profile.schedule_status)
    @conversation
  end

  private

  def merged_attributes
    @conversation.custom_attributes.merge(@attributes.slice(*ATTRIBUTE_KEYS).compact_blank)
  end

  def profile
    @profile ||= VerticalProfile.for(@conversation.account)
  end

  def next_labels
    (@conversation.label_list.to_a - open_stage_titles) | [profile.schedule_status]
  end

  def open_stage_titles
    vertical = Vertical.find_by(key: @conversation.account.custom_attributes['vertical_template'])
    return [] if vertical.blank?

    vertical.vertical_statuses.where(closes_conversation: false).pluck(:title)
  end
end
