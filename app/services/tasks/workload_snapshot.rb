# Per-agent workload aggregator used by the admin "Team Board" tab.
# Returns one row per account user with their open/overdue/due-today
# counts plus a totals dict for the top stats row.
class Tasks::WorkloadSnapshot
  def initialize(account:)
    @account = account
  end

  def call
    { agents: agents_payload, totals: totals_payload }
  end

  private

  # Build the per-agent table with four bulk-aggregated counts instead of
  # the previous N+1 (4 COUNTs per user). Each bucket is one JOIN + GROUP
  # query against `task_assignees`, so the whole table costs 4 queries
  # regardless of how many agents the account has.
  def agents_payload
    open_counts = count_by_assignee(@account.tasks.active)
    overdue_counts = count_by_assignee(@account.tasks.overdue)
    due_today_counts = count_by_assignee(
      @account.tasks.where(due_date: today_range).where(status: %i[open in_progress])
    )
    done_week_counts = count_by_assignee(
      @account.tasks.where(status: :done, completed_at: week_range)
    )

    members.map do |u|
      {
        user: { id: u.id, name: u.name, avatar_url: u.avatar_url },
        open_count: open_counts[u.id] || 0,
        overdue_count: overdue_counts[u.id] || 0,
        due_today_count: due_today_counts[u.id] || 0,
        completed_this_week: done_week_counts[u.id] || 0
      }
    end.sort_by { |row| -row[:open_count] }
  end

  # `User` carries jsonb columns that PG cannot compare for DISTINCT,
  # so we collapse to ids first and rehydrate via a single `User.where`.
  def members
    @members ||= User.where(id: @account.users.select(:id).distinct).order(:name)
  end

  # Returns { user_id => count } for the scope. Joins `task_assignees`
  # so multi-assignee tasks correctly contribute to each owner's bucket.
  def count_by_assignee(scope)
    scope.joins(:task_assignees).group('task_assignees.user_id').count
  end

  def totals_payload
    {
      open: @account.tasks.active.count,
      overdue: @account.tasks.overdue.count,
      due_today: @account.tasks.where(due_date: today_range).where(status: %i[open in_progress]).count
    }
  end

  def today_range
    Time.current.all_day
  end

  def week_range
    Time.current.all_week
  end
end
