# Create a subtask under the triggering task.
# Params:
#   title (String, required) — supports the same placeholders as
#     `send_message` (rendered against the parent task).
#   priority (String, optional) — see KanbanAutomation::PRIORITIES
#   due_in_hours (Numeric, optional) — relative due-date offset from now
class Kanban::Automations::Actions::AddSubtask < Kanban::Automations::Actions::Base
  PLACEHOLDERS = {
    '{{task_title}}' => ->(task) { task.title.to_s },
    '{{stage_name}}' => ->(task) { task.funnel_stage&.name.to_s },
    '{{funnel_name}}' => ->(task) { task.funnel&.name.to_s }
  }.freeze

  private

  def perform!
    raw_title = required_param!(:title)
    title = render_template(raw_title)
    priority = params[:priority].to_s.presence
    priority = nil unless KanbanAutomation::PRIORITIES.include?(priority)

    due_in_hours = params[:due_in_hours].presence&.to_f
    due_date = due_in_hours.present? ? Time.current + due_in_hours.hours : nil

    funnel.kanban_tasks.create!(
      account: account,
      funnel_stage: task.funnel_stage,
      parent_task: task,
      title: title.truncate(255),
      priority: priority || 'none',
      due_date: due_date
    )
  end

  def render_template(template)
    PLACEHOLDERS.reduce(template) { |acc, (token, resolver)| acc.gsub(token) { resolver.call(task).to_s } }
  end
end
