# == Schema Information
#
# Table name: kanban_task_conversations
#
#  id              :bigint           not null, primary key
#  kanban_task_id  :bigint           not null
#  conversation_id :bigint           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
class KanbanTaskConversation < ApplicationRecord
  belongs_to :kanban_task
  belongs_to :conversation

  validates :conversation_id, uniqueness: { scope: :kanban_task_id }

  after_create_commit :dispatch_conversation_attached_event

  private

  def dispatch_conversation_attached_event
    Kanban::Automations::Dispatcher.dispatch(
      :conversation_attached,
      kanban_task,
      conversation_id: conversation_id
    )
  end
end
