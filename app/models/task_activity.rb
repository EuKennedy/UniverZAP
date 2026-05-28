# == Schema Information
#
# Table name: task_activities
#
#  id          :bigint           not null, primary key
#  task_id     :bigint           not null
#  user_id     :bigint
#  action      :string           not null
#  payload     :jsonb            not null, default {}
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class TaskActivity < ApplicationRecord
  belongs_to :task
  belongs_to :user, optional: true

  ACTIONS = %w[created assigned status_changed comment_added completed due_date_changed].freeze

  validates :action, presence: true, length: { maximum: 64 }

  scope :recent_first, -> { order(created_at: :desc) }

  def push_event_data
    {
      id: id,
      task_id: task_id,
      user: user_payload,
      action: action,
      payload: payload,
      created_at: created_at.to_i
    }
  end

  private

  def user_payload
    return nil if user.blank?

    { id: user.id, name: user.name, avatar_url: user.avatar_url }
  end
end
