# Scheduled scanner that emits `task_overdue` notifications for any
# task that crossed its due_date in the last LOOKBACK window and is
# still open / in_progress / blocked. Mirrors the Kanban automation
# overdue scanner — running off-cycle from KanbanTask::OverdueScanner
# so the two domains never fight for the same dispatcher slot.
#
# Wired into `config/schedule.yml` every 15 minutes.
class Tasks::OverdueScannerJob < ApplicationJob
  queue_as :default

  # 15-min window — matches the cron cadence so each task is notified
  # once per overdue threshold crossing.
  LOOKBACK = 15.minutes

  def perform
    overdue_scope.find_each { |task| notify_assignees(task) }
  end

  private

  def overdue_scope
    Task
      .where.not(due_date: nil)
      .where(due_date: (Time.current - LOOKBACK)..Time.current)
      .where.not(status: %i[done cancelled])
  end

  def notify_assignees(task)
    task.assignees.find_each do |user|
      Tasks::Notifier.notify_overdue(task: task, user: user)
    end
  end
end
