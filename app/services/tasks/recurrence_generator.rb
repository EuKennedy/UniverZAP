require 'fugit'

# Computes the next due-date for a recurrence rule + materializes the
# next Task occurrence. The "rule" is a small hash stored on
# `tasks.recurrence_rule`:
#
#   { "type" => "daily" }
#   { "type" => "weekly",  "weekdays" => [1, 3, 5] }   # Mon/Wed/Fri
#   { "type" => "monthly", "day" => 15 }
#   { "type" => "cron",    "cron" => "0 9 * * 1-5" }   # weekday 9am
#
# We deliberately keep this stupid-simple: no leap-second math, no
# timezone-of-the-account juggling — that's a follow-up once we have
# real customer signal. `from:` always defaults to `Time.current`.
class Tasks::RecurrenceGenerator
  class InvalidRule < StandardError; end

  VALID_TYPES = %w[daily weekly monthly cron].freeze

  # Compute the next firing time for `rule` starting from `from`.
  # Returns a `Time` (Time.zone) or nil if the rule is unparseable.
  def self.next_occurrence(rule, from: Time.current)
    new(rule, from).next_occurrence
  end

  # Spawn the next concrete Task row from `parent` and reschedule
  # `parent.next_occurrence_at` so the scheduler doesn't re-fire.
  def self.spawn_next!(parent)
    new(parent.recurrence_rule, Time.current).spawn_next!(parent)
  end

  # Public wrapper used by the controller modal so the dashboard can
  # show the "Next: ..." preview without round-tripping a save.
  def self.clone_for_next(parent)
    new(parent.recurrence_rule, Time.current).clone_for_next(parent)
  end

  def initialize(rule, from)
    @rule = (rule || {}).with_indifferent_access
    @from = from || Time.current
  end

  def next_occurrence
    case type
    when 'daily'   then daily_next
    when 'weekly'  then weekly_next
    when 'monthly' then monthly_next
    when 'cron'    then cron_next
    end
  end

  def spawn_next!(parent)
    next_at = next_occurrence
    return nil if next_at.blank?

    child = clone_for_next(parent, next_at: next_at)
    # rubocop:disable Rails/SkipsModelValidations
    parent.update_columns(next_occurrence_at: next_at)
    # rubocop:enable Rails/SkipsModelValidations
    child
  end

  def clone_for_next(parent, next_at: next_occurrence)
    return nil if next_at.blank?

    child = build_child(parent, next_at)
    copy_assignees(parent, child)
    child
  end

  private

  attr_reader :rule, :from

  def type
    rule[:type].to_s
  end

  def daily_next
    (from + 1.day).beginning_of_day + nine_am_offset
  end

  def weekly_next
    days = Array(rule[:weekdays]).map(&:to_i).select { |d| d.between?(0, 6) }.uniq.sort
    return nil if days.empty?

    1.upto(7) do |offset|
      candidate = from + offset.days
      return candidate.beginning_of_day + nine_am_offset if days.include?(candidate.wday)
    end
    nil
  end

  def monthly_next
    day = rule[:day].to_i
    return nil unless day.between?(1, 31)

    target = from.beginning_of_month + nine_am_offset
    target = target.change(day: [day, target.end_of_month.day].min)
    target = (target + 1.month).change(day: [day, (from.end_of_month + 1.month).day].min) if target <= from
    target
  end

  def cron_next
    expression = rule[:cron].to_s
    return nil if expression.blank?

    Fugit::Cron.parse(expression)&.next_time(from)&.to_t&.in_time_zone
  rescue StandardError
    nil
  end

  def nine_am_offset
    9.hours
  end

  def build_child(parent, next_at)
    parent.account.tasks.create!(
      created_by_user: parent.created_by_user,
      recurrence_parent_id: parent.id,
      title: parent.title,
      description: parent.description,
      urgency: parent.urgency,
      due_date: next_at,
      notify_assignees: parent.notify_assignees,
      custom_attributes: parent.custom_attributes
    )
  end

  def copy_assignees(parent, child)
    # Use the database scope (not the in-memory association) so callers
    # who just added assignees on a cached `parent` instance still get
    # them mirrored onto the next occurrence.
    TaskAssignee.where(task_id: parent.id).find_each do |assignment|
      child.task_assignees.create!(user_id: assignment.user_id)
    end
  end
end
