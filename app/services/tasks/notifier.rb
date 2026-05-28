# Tasks::Notifier — single seam that fans a Task lifecycle event into
# a Notification row + the dashboard's push-notification pipeline.
#
# We pump everything through the existing Notification model so the
# bell-icon dropdown, FCM dispatch and email digest reuse one schema.
# task_assigned / task_due_soon / task_overdue / task_commented are
# new entries in `Notification::NOTIFICATION_TYPES` and are exposed to
# the user's email/push opt-in toggles via FlagShihTzu.
#
# `task.notify_assignees == false` is the per-task escape hatch — the
# Notifier short-circuits without touching the DB so the operator can
# create silent task rows (e.g. archive imports) without spamming.
class Tasks::Notifier
  def self.notify_assignment(task:, user:)
    return unless task.notify_assignees

    create_notification(task: task, user: user, type: :task_assigned)
  end

  def self.notify_overdue(task:, user:)
    create_notification(task: task, user: user, type: :task_overdue)
  end

  def self.notify_due_soon(task:, user:)
    create_notification(task: task, user: user, type: :task_due_soon)
  end

  def self.notify_commented(task:, user:, comment:)
    create_notification(task: task, user: user, type: :task_commented, secondary_actor: comment)
  end

  def self.create_notification(task:, user:, type:, secondary_actor: nil)
    return if task.account_id.blank? || user.blank?

    Notification.create!(
      account_id: task.account_id,
      user_id: user.id,
      notification_type: type,
      primary_actor: task,
      secondary_actor: secondary_actor
    )
  rescue StandardError => e
    Rails.logger.error("[Tasks::Notifier] type=#{type} task=#{task&.id} user=#{user&.id} failed: #{e.message}")
    nil
  end
end
