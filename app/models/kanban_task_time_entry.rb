class KanbanTaskTimeEntry < ApplicationRecord
  belongs_to :kanban_task, inverse_of: :time_entries
  belongs_to :user

  scope :open, -> { where(ended_at: nil) }
  scope :closed, -> { where.not(ended_at: nil) }

  before_save :compute_duration

  def push_event_data
    {
      id: id,
      user_id: user_id,
      user_name: user&.name,
      started_at: started_at.to_i,
      ended_at: ended_at&.to_i,
      duration_seconds: duration_seconds,
      note: note
    }
  end

  private

  def compute_duration
    return unless ended_at.present? && started_at.present?

    self.duration_seconds = (ended_at - started_at).to_i
  end
end
