class KanbanTaskActivity < ApplicationRecord
  belongs_to :kanban_task, inverse_of: :activities
  belongs_to :user, optional: true

  ACTIONS = %w[
    created
    title_changed
    stage_changed
    priority_changed
    assignees_changed
    labels_changed
    completed
    reopened
    commented
    time_started
    time_stopped
  ].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validates :summary, presence: true

  scope :recent, ->(limit = 50) { order(created_at: :desc).limit(limit) }

  def push_event_data
    {
      id: id,
      action: action,
      summary: summary,
      data: data || {},
      user_id: user_id,
      user_name: user&.name,
      created_at: created_at.to_i
    }
  end
end
