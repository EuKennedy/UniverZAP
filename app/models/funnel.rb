# == Schema Information
#
# Table name: funnels
#
#  id                  :bigint           not null, primary key
#  account_id          :bigint           not null
#  name                :string           not null
#  description         :text
#  position            :integer          default(0), not null
#  automation_settings :jsonb            default({}), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
class Funnel < ApplicationRecord
  include KanbanRealtime

  AUTOMATION_KEYS = %w[
    auto_create_task_for_new_conversation
    auto_assign_task_to_agent
    sync_task_conversation_assignees
    auto_resolve_conversation_on_task_close
    auto_win_task_on_conversation_resolve
    notify_on_task_stage_change
    tag_conversation_with_stage
  ].freeze

  belongs_to :account

  has_many :funnel_stages, -> { order(:position) }, dependent: :destroy, inverse_of: :funnel
  has_many :funnel_inboxes, dependent: :destroy
  has_many :inboxes, through: :funnel_inboxes
  has_many :funnel_agents, dependent: :destroy
  has_many :agents, through: :funnel_agents, source: :user
  has_many :kanban_tasks, dependent: :destroy
  has_many :custom_fields,
           -> { ordered },
           class_name: 'FunnelCustomField',
           dependent: :destroy,
           inverse_of: :funnel

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2000 }, allow_blank: true
  validate :validate_automation_settings

  before_validation :assign_position, on: :create

  scope :ordered, -> { order(:position, :id) }

  def automation_enabled?(key)
    ActiveModel::Type::Boolean.new.cast(automation_settings[key.to_s])
  end

  def push_event_data
    {
      id: id,
      account_id: account_id,
      name: name,
      description: description,
      position: position,
      automation_settings: automation_settings,
      inbox_ids: inbox_ids,
      agent_ids: agent_ids,
      tasks_count: kanban_tasks.count,
      stages: funnel_stages.ordered.map(&:push_event_data),
      custom_fields: custom_fields.map(&:push_event_data),
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
    # The before_validation callback fires before `belongs_to :account`
    # raises its presence error, so during shoulda-matcher introspection
    # (and any other code path that builds a Funnel without an account
    # set) `account` is `nil`. Bailing out keeps validation reachable
    # so the real error surfaces — "Account must exist" — instead of a
    # NoMethodError that masks it.
    return if account.nil?

    self.position = (account.funnels.maximum(:position) || 0) + 1
  end

  def validate_automation_settings
    return if automation_settings.blank?

    invalid = automation_settings.keys.map(&:to_s) - AUTOMATION_KEYS
    return if invalid.empty?

    errors.add(:automation_settings, "unknown keys: #{invalid.join(', ')}")
  end
end
