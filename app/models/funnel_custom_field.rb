class FunnelCustomField < ApplicationRecord
  include KanbanRealtime

  FIELD_TYPES = %i[text number date single_select multi_select].freeze

  belongs_to :funnel, inverse_of: :custom_fields
  has_many :kanban_task_custom_values, dependent: :destroy

  enum field_type: { text: 0, number: 1, date: 2, single_select: 3, multi_select: 4 }

  validates :name, presence: true, length: { maximum: 80 }
  validate :validate_options_for_select

  before_validation :assign_position, on: :create

  scope :ordered, -> { order(:position, :id) }

  delegate :account, to: :funnel

  def push_event_data
    {
      id: id,
      funnel_id: funnel_id,
      name: name,
      field_type: field_type,
      options: options || {},
      position: position,
      required: required,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i
    }
  end

  private

  def kanban_event_payload
    push_event_data
  end

  def assign_position
    return if position.present? && position.positive?

    self.position = (funnel&.custom_fields&.maximum(:position) || 0) + 1
  end

  def validate_options_for_select
    return unless %w[single_select multi_select].include?(field_type.to_s)

    choices = options['choices']
    return if choices.is_a?(Array) && choices.any? && choices.all? { |c| c.is_a?(String) && c.present? }

    errors.add(:options, :missing_choices, message: 'select fields require non-empty string choices')
  end
end
