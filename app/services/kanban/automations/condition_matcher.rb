# Evaluates a rule's `conditions` JSON against the task + event payload.
# Returns true only when EVERY condition matches (AND semantics).
# An empty conditions hash always matches.
#
# Supported keys (event-agnostic):
#   priority_in:        ['high', 'urgent']
#   priority_not_in:    ['low']
#   has_label:          'urgent'      | ['urgent', 'vip']    — title or array (all must be present)
#   missing_label:      'qualified'   | ['churn-risk']
#   stage_id_in:        [3, 4]        — current funnel_stage_id
#   funnel_id_in:       [1, 2]
#   assignee_id_in:     [10, 11]
#   has_assignee:       true | false  — present/absent
#   has_due_date:       true | false
#   due_in_hours_lte:   24            — task.due_date <= now + N.hours
#
# Event-specific keys (only checked when the event provides them):
#   from_stage_id_in:   [...]         — task_moved_to_stage event
#   to_stage_id_in:     [...]
#   from_funnel_id_in:  [...]         — task_moved_to_funnel event
#   to_funnel_id_in:    [...]
#
# Unknown keys cause the match to fail closed so a typo never silently
# disables the entire filter.
class Kanban::Automations::ConditionMatcher
  SUPPORTED_KEYS = %w[
    priority_in priority_not_in
    has_label missing_label
    stage_id_in funnel_id_in
    assignee_id_in has_assignee
    has_due_date due_in_hours_lte
    from_stage_id_in to_stage_id_in
    from_funnel_id_in to_funnel_id_in
  ].freeze

  def self.matches?(rule:, task:, event_payload: {})
    new(rule: rule, task: task, event_payload: event_payload).matches?
  end

  def initialize(rule:, task:, event_payload: {})
    @rule = rule
    @task = task
    @event_payload = (event_payload || {}).with_indifferent_access
    @conditions = (rule.conditions || {}).with_indifferent_access
  end

  def matches?
    return true if @conditions.empty?

    @conditions.all? { |key, value| evaluate(key.to_s, value) }
  end

  private

  attr_reader :task, :event_payload

  def evaluate(key, value)
    return false unless SUPPORTED_KEYS.include?(key)

    send("matches_#{key}?", value)
  end

  def matches_priority_in?(values)
    Array(values).map(&:to_s).include?(task.priority.to_s)
  end

  def matches_priority_not_in?(values)
    Array(values).map(&:to_s).exclude?(task.priority.to_s)
  end

  def matches_has_label?(values)
    required = Array(values).map { |v| v.to_s.strip.downcase }
    titles = task.task_labels.includes(:label).map { |tl| tl.label.title.to_s.downcase }
    (required - titles).empty?
  end

  def matches_missing_label?(values)
    required = Array(values).map { |v| v.to_s.strip.downcase }
    titles = task.task_labels.includes(:label).map { |tl| tl.label.title.to_s.downcase }
    (required & titles).empty?
  end

  def matches_stage_id_in?(values)
    Array(values).map(&:to_i).include?(task.funnel_stage_id)
  end

  def matches_funnel_id_in?(values)
    Array(values).map(&:to_i).include?(task.funnel_id)
  end

  def matches_assignee_id_in?(values)
    (Array(values).map(&:to_i) & task.assignee_ids).any?
  end

  def matches_has_assignee?(expected)
    expected_bool = ActiveModel::Type::Boolean.new.cast(expected)
    expected_bool ? task.assignee_ids.any? : task.assignee_ids.empty?
  end

  def matches_has_due_date?(expected)
    expected_bool = ActiveModel::Type::Boolean.new.cast(expected)
    expected_bool ? task.due_date.present? : task.due_date.blank?
  end

  def matches_due_in_hours_lte?(hours)
    return false if task.due_date.blank?

    task.due_date <= Time.current + hours.to_f.hours
  end

  def matches_from_stage_id_in?(values)
    from = event_payload[:from_stage_id]
    return false if from.blank?

    Array(values).map(&:to_i).include?(from.to_i)
  end

  def matches_to_stage_id_in?(values)
    to = event_payload[:to_stage_id]
    return false if to.blank?

    Array(values).map(&:to_i).include?(to.to_i)
  end

  def matches_from_funnel_id_in?(values)
    from = event_payload[:from_funnel_id]
    return false if from.blank?

    Array(values).map(&:to_i).include?(from.to_i)
  end

  def matches_to_funnel_id_in?(values)
    to = event_payload[:to_funnel_id]
    return false if to.blank?

    Array(values).map(&:to_i).include?(to.to_i)
  end
end
