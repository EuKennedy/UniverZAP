# == Schema Information
#
# Table name: task_assignees
#
#  id          :bigint           not null, primary key
#  task_id     :bigint           not null
#  user_id     :bigint           not null
#  notified_at :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes:
#   index_task_assignees_on_task_id_and_user_id (unique)
#
class TaskAssignee < ApplicationRecord
  belongs_to :task
  belongs_to :user

  validates :user_id, uniqueness: { scope: :task_id }

  after_create_commit :log_assignment
  after_create_commit :broadcast_assigned
  after_create_commit :notify_user

  private

  def log_assignment
    task.task_activities.create!(
      user: task.created_by_user,
      action: 'assigned',
      payload: { assignee_id: user_id, assignee_name: user.name }
    )
  end

  def broadcast_assigned
    Tasks::Broadcaster.broadcast('task.assignee_added', task, target: :account,
                                                              payload: assignee_payload)
    Tasks::Broadcaster.broadcast('task.assigned_to_you', task, target: :user, user: user)
  end

  def notify_user
    return unless task.notify_assignees

    Tasks::Notifier.notify_assignment(task: task, user: user)
    update_columns(notified_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def assignee_payload
    {
      task_id: task_id,
      assignee: { id: user.id, name: user.name, avatar_url: user.avatar_url }
    }
  end
end
