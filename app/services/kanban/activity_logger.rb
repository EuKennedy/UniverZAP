class Kanban::ActivityLogger
  class << self
    def log_created(task, user)
      write(task, user, action: 'created', summary: "Task \"#{truncate(task.title)}\" was created.")
    end

    def log_changes(task, user, changes_snapshot, previous_assignee_ids: nil, previous_label_ids: nil)
      log_title_change(task, user, changes_snapshot)
      log_stage_change(task, user, changes_snapshot)
      log_priority_change(task, user, changes_snapshot)
      log_completion_change(task, user, changes_snapshot)
      log_assignees_change(task, user, previous_assignee_ids) if previous_assignee_ids
      log_labels_change(task, user, previous_label_ids) if previous_label_ids
    end

    def log_time_started(task, user)
      write(task, user, action: 'time_started', summary: "#{user&.name || 'Someone'} started tracking time.")
    end

    def log_time_stopped(task, user, duration_seconds)
      write(
        task,
        user,
        action: 'time_stopped',
        summary: "#{user&.name || 'Someone'} stopped tracking after #{format_duration(duration_seconds)}.",
        data: { duration_seconds: duration_seconds }
      )
    end

    private

    def log_title_change(task, user, changes_snapshot)
      return unless changes_snapshot.key?('title')

      from, to = changes_snapshot['title']
      write(task, user, action: 'title_changed', summary: "Title changed from \"#{truncate(from)}\" to \"#{truncate(to)}\".")
    end

    def log_stage_change(task, user, changes_snapshot)
      return unless changes_snapshot.key?('funnel_stage_id')

      stage_name = task.funnel_stage&.name
      write(task, user, action: 'stage_changed', summary: "Moved to stage \"#{stage_name}\".")
    end

    def log_priority_change(task, user, changes_snapshot)
      return unless changes_snapshot.key?('priority')

      _from, to = changes_snapshot['priority']
      write(task, user, action: 'priority_changed', summary: "Priority set to #{KanbanTask.priorities.key(to) || to}.")
    end

    def log_completion_change(task, user, changes_snapshot)
      return unless changes_snapshot.key?('completed_at')

      action = task.completed_at.present? ? 'completed' : 'reopened'
      summary = task.completed_at.present? ? 'Task marked as completed.' : 'Task reopened.'
      write(task, user, action: action, summary: summary)
    end

    def log_assignees_change(task, user, previous_assignee_ids)
      next_ids = task.assignee_ids
      return if next_ids.sort == previous_assignee_ids.sort

      added = (next_ids - previous_assignee_ids).size
      removed = (previous_assignee_ids - next_ids).size
      write(task, user, action: 'assignees_changed', summary: "Assignees changed (+#{added}, -#{removed}).")
    end

    def log_labels_change(task, user, previous_label_ids)
      next_ids = task.task_label_ids
      return if next_ids.sort == previous_label_ids.sort

      write(task, user, action: 'labels_changed', summary: 'Labels updated.')
    end

    # Activity rows are an observability nice-to-have. Failing to write one
    # must never roll back the parent task save — most commonly this fires
    # when a node hasn't picked up the latest kanban migrations yet
    # (PG::UndefinedTable on kanban_task_activities). Log + swallow so the
    # UI keeps working and we can find the issue in Sentry.
    def write(task, user, attrs)
      task.activities.create!(attrs.merge(user: user))
    rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[Kanban::ActivityLogger] skipped #{attrs[:action]} for task=#{task.id}: #{e.class} #{e.message}")
      ChatwootExceptionTracker.new(e, user: user, account: task.account).capture_exception if defined?(ChatwootExceptionTracker)
    end

    def truncate(value)
      value.to_s.truncate(60)
    end

    def format_duration(seconds)
      return '0s' if seconds.to_i.zero?

      total = seconds.to_i
      hours = total / 3600
      minutes = (total % 3600) / 60
      [hours.positive? ? "#{hours}h" : nil, minutes.positive? ? "#{minutes}m" : nil].compact.join(' ').presence || "#{total}s"
    end
  end
end
