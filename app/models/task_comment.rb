# == Schema Information
#
# Table name: task_comments
#
#  id          :bigint           not null, primary key
#  task_id     :bigint           not null
#  user_id     :bigint           not null
#  body        :jsonb            not null, default {}
#  edited_at   :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class TaskComment < ApplicationRecord
  belongs_to :task
  belongs_to :user

  validates :body, presence: true

  after_create_commit :log_activity
  after_create_commit :broadcast_added

  def push_event_data
    {
      id: id,
      task_id: task_id,
      user: { id: user.id, name: user.name, avatar_url: user.avatar_url },
      body: body,
      edited_at: edited_at&.to_i,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i
    }
  end

  private

  def log_activity
    task.task_activities.create!(
      user: user,
      action: 'comment_added',
      payload: { comment_id: id }
    )
  end

  def broadcast_added
    Tasks::Broadcaster.broadcast('task.comment_added', task, target: :account,
                                                             payload: push_event_data)
  end
end
