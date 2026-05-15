# == Schema Information
#
# Table name: funnel_stages
#
#  id          :bigint           not null, primary key
#  funnel_id   :bigint           not null
#  name        :string           not null
#  description :text
#  color       :string           default("#64748B"), not null
#  position    :integer          default(0), not null
#  status_type :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class FunnelStage < ApplicationRecord
  include KanbanRealtime

  HEX_COLOR_REGEX = /\A#(?:[0-9a-fA-F]{3}){1,2}\z/

  belongs_to :funnel, inverse_of: :funnel_stages
  has_many :kanban_tasks, dependent: :restrict_with_error

  enum status_type: { active: 0, won: 1, lost: 2 }

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2000 }, allow_blank: true
  validates :color, format: { with: HEX_COLOR_REGEX, message: 'must be a hex color' }

  before_validation :assign_position, on: :create

  scope :ordered, -> { order(:position, :id) }

  delegate :account, to: :funnel

  def push_event_data
    {
      id: id,
      funnel_id: funnel_id,
      name: name,
      description: description,
      color: color,
      position: position,
      status_type: status_type,
      tasks_count: kanban_tasks.count,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i
    }
  end

  private

  def kanban_event_payload
    push_event_data
  end

  def kanban_destroyed_payload
    { id: id, funnel_id: funnel_id }
  end

  def assign_position
    return if position.present? && position.positive?

    self.position = (funnel&.funnel_stages&.maximum(:position) || 0) + 1
  end
end
