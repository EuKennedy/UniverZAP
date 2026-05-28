# Runs every action defined on a `KanbanAutomation` rule against a
# specific task. Each action is wrapped in `Kanban::Automations::Actions::*`
# strategy class; critical actions abort the rule, non-critical ones
# record their error and let subsequent actions continue.
#
# The executor itself never raises — failure is recorded on the rule
# via `record_error!` so an admin can see what happened in the UI.
class Kanban::Automations::Executor
  REGISTRY = {
    'send_message' => Kanban::Automations::Actions::SendMessage,
    'assign_user' => Kanban::Automations::Actions::AssignUser,
    'unassign_users' => Kanban::Automations::Actions::UnassignUsers,
    'move_to_stage' => Kanban::Automations::Actions::MoveToStage,
    'move_to_funnel' => Kanban::Automations::Actions::MoveToFunnel,
    'add_subtask' => Kanban::Automations::Actions::AddSubtask,
    'add_label' => Kanban::Automations::Actions::AddLabel,
    'remove_label' => Kanban::Automations::Actions::RemoveLabel,
    'set_priority' => Kanban::Automations::Actions::SetPriority,
    'set_due_date' => Kanban::Automations::Actions::SetDueDate,
    'webhook' => Kanban::Automations::Actions::Webhook,
    'resolve_conversation' => Kanban::Automations::Actions::ResolveConversation
  }.freeze

  def self.call(rule:, task:, event_payload: {})
    new(rule: rule, task: task, event_payload: event_payload).call
  end

  def initialize(rule:, task:, event_payload: {})
    @rule = rule
    @task = task
    @event_payload = event_payload || {}
  end

  def call
    return :skipped_inactive unless @rule.active?
    return :skipped_no_match unless Kanban::Automations::ConditionMatcher.matches?(
      rule: @rule, task: @task, event_payload: @event_payload
    )

    execute_actions
    @rule.record_run!
    :ok
  rescue StandardError => e
    Rails.logger.error("[Kanban automation] rule=#{@rule.id} task=#{@task&.id} failed: #{e.message}")
    @rule.record_error!(e.message)
    :failed
  end

  private

  def execute_actions
    @rule.actions_array.each_with_index do |action_hash, idx|
      type = action_hash[:type].to_s
      klass = REGISTRY[type]
      next log_unknown_action(type, idx) if klass.nil?

      run_action(klass, action_hash, idx)
    end
  end

  def run_action(klass, action_hash, idx)
    action = klass.new(
      task: @task,
      params: action_hash[:params] || {},
      event_payload: @event_payload
    )
    action.call
  rescue Kanban::Automations::Actions::Base::ExecutionError => e
    # Critical actions propagate — they abort the whole rule and bubble
    # up to the executor's `rescue` which records the error. Non-critical
    # ones we log and continue, mirroring n8n's "Continue on fail".
    raise if action&.critical?

    Rails.logger.warn(
      "[Kanban automation] rule=#{@rule.id} action=#{klass.name}[#{idx}] non-critical skip: #{e.message}"
    )
  end

  def log_unknown_action(type, idx)
    Rails.logger.warn(
      "[Kanban automation] rule=#{@rule.id} action[#{idx}] type=#{type.inspect} not in registry — skipped"
    )
  end
end
