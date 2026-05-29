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

  def agents_payload
    members.map { |u| agent_row(u) }.sort_by { |row| -row[:open_count] }
  end

  def members
    @members ||= @account.users.distinct
  end

  def agent_row(user)
    assigned = assigned_scope(user)
    {
      user: { id: user.id, name: user.name, avatar_url: user.avatar_url },
      open_count: assigned.active.count,
      overdue_count: assigned.overdue.count,
      due_today_count: assigned.where(due_date: today_range).where(status: %i[open in_progress]).count,
      completed_this_week: assigned.where(status: :done, completed_at: week_range).count
    }
  end

  def assigned_scope(user)
    @account.tasks.assigned_to(user.id)
  end

  def totals_payload
    {
      open: @account.tasks.active.count,
      overdue: @account.tasks.overdue.count,
      due_today: @account.tasks.where(due_date: today_range).where(status: %i[open in_progress]).count
    }
  end

  def today_range
    Time.current.beginning_of_day..Time.current.end_of_day
  end

  def week_range
    Time.current.beginning_of_week..Time.current.end_of_week
  end
end
