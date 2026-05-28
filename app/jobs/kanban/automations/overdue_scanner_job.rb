# Scheduled scanner that fires `task_overdue` events for any open task
# whose due_date passed in the last interval and hasn't been completed
# yet. Idempotency lives in Sidekiq itself (singleton schedule) — if
# you want per-task once-only semantics, add a condition on the rule
# (e.g. `due_in_hours_lte: 0` + a label that the rule applies on first
# trigger so subsequent runs no-op).
#
# Wired into `config/schedule.yml` to run every 5 minutes by default.
class Kanban::Automations::OverdueScannerJob < ApplicationJob
  queue_as :default

  # Re-emit `task_overdue` only for tasks that crossed the deadline in
  # the last LOOKBACK window. Without this guard a daily scan would
  # blast every overdue card every run.
  LOOKBACK = 15.minutes

  def perform
    KanbanTask
      .where.not(due_date: nil)
      .where(due_date: (Time.current - LOOKBACK)..Time.current)
      .where(completed_at: nil)
      .find_each do |task|
      Kanban::Automations::Dispatcher.dispatch(:task_overdue, task, due_date: task.due_date.to_i)
    end
  end
end
