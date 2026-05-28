# Sidekiq worker that executes a single KanbanAutomation rule against a
# single task. Decoupled from the dispatcher so a slow action (HTTP
# webhook, bulk message send) never blocks the model callback that
# fired the event.
#
# Args are scalar (rule_id, task_id, payload Hash) — never pass AR
# objects to Sidekiq.
class Kanban::Automations::RunJob < ApplicationJob
  queue_as :default

  def perform(rule_id, task_id, event_payload = {})
    rule = KanbanAutomation.find_by(id: rule_id)
    task = KanbanTask.find_by(id: task_id)
    return unless rule && task

    # Defense-in-depth: never run a rule against a task from a
    # different tenant. The dispatcher already filters by account_id
    # but the job mustn't trust its callers.
    if rule.account_id != task.account_id
      Rails.logger.error(
        "[Kanban automation] TENANT MISMATCH rule=#{rule_id} (account=#{rule.account_id}) " \
        "task=#{task_id} (account=#{task.account_id}) — refused"
      )
      return
    end

    Kanban::Automations::Executor.call(
      rule: rule,
      task: task,
      event_payload: event_payload || {}
    )
  end
end
