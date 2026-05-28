# Detach a label (by title) from the task. Idempotent — no error if the
# label was already absent.
# Params:
#   label (String, required)
class Kanban::Automations::Actions::RemoveLabel < Kanban::Automations::Actions::Base
  private

  def perform!
    title = required_param!(:label).to_s.strip.downcase
    label = account.labels.find_by(title: title)
    return if label.nil?

    task.task_labels.where(label_id: label.id).destroy_all
  end
end
