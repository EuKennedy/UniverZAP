class Ai::Intent < ApplicationRecord
  self.table_name = 'ai_intents'

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account

  ACTIONS = %w[auto_reply route_to_team add_label create_kanban_task escalate_human silence].freeze

  validates :name, presence: true, length: { maximum: 80 }
  validates :action, inclusion: { in: ACTIONS }

  scope :active, -> { where(active: true).order(:position) }

  def trigger_list
    triggers.to_s.split(',').map { |t| t.strip.downcase }.reject(&:blank?)
  end

  def matches?(text)
    return false if text.blank?

    body = text.to_s.downcase
    trigger_list.any? { |t| body.include?(t) }
  end

  def push_event_data
    {
      id: id,
      name: name,
      triggers: triggers,
      action: action,
      action_payload: action_payload,
      active: active,
      position: position
    }
  end
end
