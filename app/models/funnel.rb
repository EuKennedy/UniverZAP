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
  AUTOMATION_KEYS = %w[
    auto_create_task_for_new_conversation
    auto_assign_task_to_agent
    sync_task_conversation_assignees
    auto_resolve_conversation_on_task_close
    auto_win_task_on_conversation_resolve
  ].freeze

  belongs_to :account

  has_many :funnel_stages, -> { order(:position) }, dependent: :destroy, inverse_of: :funnel
  has_many :funnel_inboxes, dependent: :destroy
  has_many :inboxes, through: :funnel_inboxes
  has_many :funnel_agents, dependent: :destroy
  has_many :agents, through: :funnel_agents, source: :user
  has_many :kanban_tasks, dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2000 }, allow_blank: true
  validate :validate_automation_settings

  before_validation :assign_position, on: :create

  scope :ordered, -> { order(:position, :id) }

  def automation_enabled?(key)
    ActiveModel::Type::Boolean.new.cast(automation_settings[key.to_s])
  end

  private

  def assign_position
    return if position.present? && position.positive?

    self.position = (account.funnels.maximum(:position) || 0) + 1
  end

  def validate_automation_settings
    return if automation_settings.blank?

    invalid = automation_settings.keys.map(&:to_s) - AUTOMATION_KEYS
    return if invalid.empty?

    errors.add(:automation_settings, "unknown keys: #{invalid.join(', ')}")
  end
end
