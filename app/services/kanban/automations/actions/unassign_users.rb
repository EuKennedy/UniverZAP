# Clear all assignees from the task. No params.
class Kanban::Automations::Actions::UnassignUsers < Kanban::Automations::Actions::Base
  private

  def perform!
    task.assignee_ids = []
  end
end
