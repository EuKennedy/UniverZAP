# == Schema Information
#
# Table name: kanban_task_labels
#
#  id             :bigint           not null, primary key
#  kanban_task_id :bigint           not null
#  label_id       :bigint           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class KanbanTaskLabel < ApplicationRecord
  belongs_to :kanban_task
  belongs_to :label

  validates :label_id, uniqueness: { scope: :kanban_task_id }
end
