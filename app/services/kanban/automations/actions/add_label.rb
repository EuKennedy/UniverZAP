# Attach a label (by title) to the task. Creates the label on the
# account if it doesn't exist yet (matches the dashboard's free-text
# label workflow).
# Params:
#   label (String, required) — case-insensitive title; will be parameterized
class Kanban::Automations::Actions::AddLabel < Kanban::Automations::Actions::Base
  private

  def perform!
    title = required_param!(:label).to_s.strip.downcase
    raise ExecutionError, 'label cannot be blank' if title.blank?

    label = account.labels.find_or_create_by!(title: title) do |new_label|
      # Default color picked from the account palette if the label has
      # to be created. Operator can recolour after the fact.
      new_label.color = '#1f93ff'
    end
    return if task.task_labels.exists?(label_id: label.id)

    task.task_labels.create!(label: label)
  end
end
