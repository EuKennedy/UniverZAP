# Materializes a Task as a KanbanTask in the chosen funnel/stage and
# cross-links the two rows so the dashboard can navigate either way.
# We don't destroy the source Task — it stays in the list and gets a
# `kanban_card_id` breadcrumb in `custom_attributes`.
class Tasks::KanbanConverter
  def initialize(task:, funnel:, stage:)
    @task = task
    @funnel = funnel
    @stage = stage
  end

  def call
    Task.transaction do
      card = build_card
      copy_assignees(card)
      cross_link(card)
      card
    end
  end

  private

  def build_card
    @task.account.kanban_tasks.create!(
      funnel: @funnel,
      funnel_stage: @stage,
      title: @task.title,
      description: description_text,
      priority: priority_from_urgency,
      due_date: @task.due_date
    )
  end

  def description_text
    raw = @task.description
    return nil if raw.blank?

    return raw if raw.is_a?(String)

    raw['text'] || raw[:text] || raw.to_s
  end

  def priority_from_urgency
    map = { 'none' => :none, 'low' => :low, 'medium' => :medium,
            'high' => :high, 'urgent' => :urgent }
    map[@task.urgency] || :none
  end

  def copy_assignees(card)
    @task.task_assignees.find_each do |assignment|
      card.kanban_task_assignees.create!(user_id: assignment.user_id)
    end
  end

  def cross_link(card)
    attrs = (@task.custom_attributes || {}).merge('kanban_card_id' => card.id)
    @task.update!(custom_attributes: attrs)
  end
end
