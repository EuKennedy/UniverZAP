# == Schema Information
#
# Table name: kanban_task_assignees
#
#  id             :bigint           not null, primary key
#  kanban_task_id :bigint           not null
#  user_id        :bigint           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class KanbanTaskAssignee < ApplicationRecord
  belongs_to :kanban_task
  belongs_to :user

  validates :user_id, uniqueness: { scope: :kanban_task_id }

  after_create_commit :dispatch_task_assigned_event

  private

  def dispatch_task_assigned_event
    Kanban::Automations::Dispatcher.dispatch(:task_assigned, kanban_task, user_id: user_id)
  end
end
