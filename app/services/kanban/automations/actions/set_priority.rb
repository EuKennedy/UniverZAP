# Force the task's priority to a fixed value.
# Params:
#   priority (String, required) — one of KanbanAutomation::PRIORITIES
class Kanban::Automations::Actions::SetPriority < Kanban::Automations::Actions::Base
  private

  def perform!
    priority = required_param!(:priority).to_s
    raise ExecutionError, "invalid priority=#{priority}" unless KanbanAutomation::PRIORITIES.include?(priority)
    return if task.priority.to_s == priority

    task.update!(priority: priority)
  end
end
