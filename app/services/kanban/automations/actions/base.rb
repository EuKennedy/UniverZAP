# Strategy-pattern base for every kanban automation action.
#
# Subclasses implement `#perform!` and may raise `ExecutionError` to
# abort the rule (the executor decides whether to rollback or skip the
# action depending on its `critical?` flag — default: non-critical).
# Subclasses receive:
#   - `task` (KanbanTask)            — the card that triggered the event
#   - `params` (HashWithIndifferentAccess) — action[:params] from the JSON
#   - `event_payload` (Hash)         — extra data the dispatcher passed
#                                       (e.g. from/to stage on a move)
#
# Critical actions abort the entire executor on failure; non-critical
# actions log + record the error but let subsequent actions run. This
# mirrors n8n / Zapier's "Continue on fail" semantics.
class Kanban::Automations::Actions::Base
  class ExecutionError < StandardError; end

  attr_reader :task, :params, :event_payload

  def initialize(task:, params:, event_payload: {})
    @task = task
    @params = (params || {}).with_indifferent_access
    @event_payload = event_payload || {}
  end

  def call
    perform!
  rescue ExecutionError => e
    Rails.logger.warn(
      "[Kanban automation] action=#{self.class.name} task=#{task&.id} failed: #{e.message}"
    )
    raise
  rescue StandardError => e
    # Wrap unexpected failures so the executor sees a uniform error type
    # and can decide how to record it on the rule.
    raise ExecutionError, "#{self.class.name}: #{e.message}"
  end

  # Override in subclasses that must abort the whole rule on failure
  # (e.g. an `assign_user` typo shouldn't kill a follow-up
  # `send_message` — but a `move_to_funnel` with a bad funnel_id is
  # almost always a config bug worth surfacing loudly).
  def critical?
    false
  end

  private

  def perform!
    raise NotImplementedError, "#{self.class.name} must implement #perform!"
  end

  # Helpers reused by multiple actions.

  def account
    task.account
  end

  def funnel
    task.funnel
  end

  def required_param!(key)
    value = params[key]
    raise ExecutionError, "missing required param: #{key}" if value.nil? || value.to_s.empty?

    value
  end
end
