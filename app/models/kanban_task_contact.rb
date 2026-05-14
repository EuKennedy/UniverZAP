# == Schema Information
#
# Table name: kanban_task_contacts
#
#  id             :bigint           not null, primary key
#  kanban_task_id :bigint           not null
#  contact_id     :bigint           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class KanbanTaskContact < ApplicationRecord
  belongs_to :kanban_task
  belongs_to :contact

  validates :contact_id, uniqueness: { scope: :kanban_task_id }
end
