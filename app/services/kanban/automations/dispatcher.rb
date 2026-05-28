# Single entry point for event → automation rule fan-out. Callbacks +
# scheduled jobs call `Dispatcher.dispatch(:event_name, task, payload)`
# and it figures out which rules match, then enqueues an async run for
# each (so the triggering callback returns immediately and a slow
# webhook never blocks the dashboard).
#
# Dispatcher logic:
#   1. Resolve rules: `account_id=task.account_id AND event_name=event
#      AND active=true AND (funnel_id IS NULL OR funnel_id=task.funnel_id)`
#   2. For each rule, enqueue `RunJob` with rule_id + task_id + payload
#   3. The job calls `Executor.call` so all the heavy lifting (HTTP,
#      DB writes, fan-out) happens off the calling thread.
#
# `event_payload` is a small hash (≤4-5 keys) safe to serialise to
# Sidekiq. Never pass full ActiveRecord objects — Sidekiq stores args
# as JSON.
class Kanban::Automations::Dispatcher
  # Per-thread depth counter to prevent runaway automation cascades.
  # When a rule action (move_to_stage, assign_user, ...) mutates the
  # task it triggers another lifecycle callback which could fan out
  # to N more rules. We allow up to MAX_DEPTH nested dispatches —
  # enough for legitimate chains (move → assign → notify) without
  # letting a misconfigured rule loop forever.
  MAX_DEPTH = 5
  DEPTH_KEY = :kanban_automation_dispatch_depth

  def self.dispatch(event_name, task, event_payload = {})
    return if task.blank? || task.account_id.blank?
    return unless KanbanAutomation::EVENTS.include?(event_name.to_s)
    return guard_overflow(event_name, task) if depth >= MAX_DEPTH

    increment_depth
    enqueue_matching_rules(event_name.to_s, task, event_payload)
  rescue StandardError => e
    # Dispatcher runs inside an after_commit callback. A failure here
    # must NOT bubble up and break the source transaction — log and
    # swallow so the user-visible kanban operation still succeeds.
    Rails.logger.error("[Kanban automation] dispatch event=#{event_name} task=#{task&.id} failed: #{e.message}")
  ensure
    decrement_depth
  end

  def self.enqueue_matching_rules(event_name, task, event_payload)
    rules = matching_rules(event_name, task)
    return if rules.empty?

    rules.find_each do |rule|
      Kanban::Automations::RunJob.perform_later(
        rule.id,
        task.id,
        (event_payload || {}).deep_stringify_keys
      )
    end
  end

  def self.depth
    Thread.current[DEPTH_KEY] ||= 0
  end

  def self.increment_depth
    Thread.current[DEPTH_KEY] = depth + 1
  end

  def self.decrement_depth
    return if Thread.current[DEPTH_KEY].nil?

    Thread.current[DEPTH_KEY] = [depth - 1, 0].max
  end

  def self.guard_overflow(event_name, task)
    Rails.logger.warn(
      "[Kanban automation] dispatch depth limit (#{MAX_DEPTH}) hit — " \
      "skipping event=#{event_name} task=#{task.id} to prevent runaway cascade"
    )
    nil
  end

  def self.matching_rules(event_name, task)
    KanbanAutomation
      .active
      .for_account(task.account_id)
      .for_event(event_name)
      .for_funnel_or_account_wide(task.funnel_id)
  end
end
