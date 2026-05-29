# Hourly scheduler that materializes the next concrete Task for every
# recurring template whose `next_occurrence_at` is due. The `done`
# callback covers the common path (user ticks a recurring task → next
# one is spawned immediately); this job picks up the long-tail (tasks
# left open past their next firing, deferred tasks, etc.).
#
# Wired into `config/schedule.yml` to run at `:00` every hour.
class Tasks::RecurrenceSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    Task.due_for_recurrence.find_each do |parent|
      Tasks::RecurrenceGenerator.spawn_next!(parent)
    rescue StandardError => e
      Rails.logger.error("[Tasks::RecurrenceScheduler] task=#{parent.id} failed: #{e.message}")
    end
  end
end
