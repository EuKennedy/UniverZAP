# Aggregates the Tasks Reports tab: 4 charts powered by single-pass
# SQL where possible. We intentionally keep everything single-account
# scoped — cross-tenant reads have no business reaching this service.
class Tasks::ReportsSnapshot
  def initialize(account:, from:, to:)
    @account = account
    @from = from.to_date
    @to = to.to_date
  end

  def call
    {
      created_vs_completed: created_vs_completed,
      avg_time_to_complete_by_agent: avg_time_by_agent,
      overdue_rate_by_agent: overdue_rate_by_agent,
      open_urgency_distribution: urgency_distribution
    }
  end

  private

  def created_vs_completed
    created = group_count_by_day(scoped_tasks.where(created_at: range_boundary), :created_at)
    completed = group_count_by_day(scoped_tasks.where(completed_at: range_boundary), :completed_at)
    days.map { |day| { date: day.iso8601, created: created[day] || 0, completed: completed[day] || 0 } }
  end

  def avg_time_by_agent
    # `avatar_url` is a User method (not a column), so we group + pluck
    # on the columns we have, and hydrate the URL via `User.find` once
    # per row at the end.
    rows = scoped_tasks
           .where.not(completed_at: nil)
           .where(completed_at: range_boundary)
           .joins(task_assignees: :user)
           .group('users.id', 'users.name')
           .pluck(Arel.sql('users.id, users.name,
                            AVG(EXTRACT(EPOCH FROM (tasks.completed_at - tasks.created_at)) / 3600.0)'))
    user_index = User.where(id: rows.map(&:first)).index_by(&:id)
    rows.map { |id, name, avg_hours| agent_avg_row(id, name, user_index[id]&.avatar_url, avg_hours) }
  end

  def agent_avg_row(id, name, avatar, avg_hours)
    {
      user: { id: id, name: name, avatar_url: avatar },
      avg_hours: avg_hours.to_f.round(2)
    }
  end

  def overdue_rate_by_agent
    members.filter_map { |user| overdue_rate_row(user) }
  end

  def overdue_rate_row(user)
    assigned = @account.tasks.assigned_to(user.id).where(created_at: range_boundary)
    total = assigned.count
    return nil if total.zero?

    overdue = assigned.overdue.count
    {
      user: { id: user.id, name: user.name, avatar_url: user.avatar_url },
      rate: (overdue.to_f / total).round(3)
    }
  end

  def urgency_distribution
    counts = @account.tasks.active.group(:urgency).count
    %w[urgent high medium low none].index_with { |key| counts[Task.urgencies[key]] || 0 }
  end

  def scoped_tasks
    @account.tasks
  end

  # See `WorkloadSnapshot#members` for why we collapse to ids first.
  def members
    @members ||= User.where(id: @account.users.select(:id).distinct).order(:name)
  end

  def days
    @days ||= (@from..@to).to_a
  end

  def range_boundary
    @from.beginning_of_day..@to.end_of_day
  end

  def group_count_by_day(scope, column)
    scope.group("DATE(#{column})").count.transform_keys do |key|
      key.is_a?(Date) ? key : Date.parse(key.to_s)
    end
  end
end
