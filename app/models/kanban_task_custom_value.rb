class KanbanTaskCustomValue < ApplicationRecord
  belongs_to :kanban_task, inverse_of: :custom_values
  belongs_to :funnel_custom_field

  validates :funnel_custom_field_id, uniqueness: { scope: :kanban_task_id }
  validate :validate_against_field

  def coerced_value
    return nil if value.blank?

    case funnel_custom_field.field_type
    when 'number' then Float(value, exception: false)
    when 'date' then Date.parse(value).to_s
    when 'multi_select' then JSON.parse(value)
    else value
    end
  rescue JSON::ParserError
    value
  end

  def push_event_data
    {
      id: id,
      funnel_custom_field_id: funnel_custom_field_id,
      value: value,
      coerced_value: coerced_value
    }
  end

  private

  def validate_against_field
    return if funnel_custom_field.blank? || value.blank?

    case funnel_custom_field.field_type
    when 'number' then validate_number
    when 'date' then validate_date
    when 'single_select' then validate_single_choice
    when 'multi_select' then validate_multi_choices
    end
  end

  def validate_number
    Float(value)
  rescue ArgumentError, TypeError
    errors.add(:value, :not_a_number)
  end

  def validate_date
    Date.parse(value)
  rescue Date::Error
    errors.add(:value, :invalid_date)
  end

  def validate_single_choice
    return if funnel_custom_field.options['choices']&.include?(value)

    errors.add(:value, :not_in_choices)
  end

  def validate_multi_choices
    parsed = JSON.parse(value)
    return errors.add(:value, :not_an_array) unless parsed.is_a?(Array)

    invalid = parsed - (funnel_custom_field.options['choices'] || [])
    errors.add(:value, :not_in_choices) if invalid.any?
  rescue JSON::ParserError
    errors.add(:value, :not_an_array)
  end
end
