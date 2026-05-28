# Close every open conversation attached to the task.
# Use when a card lands in a "won/lost" stage and the operator wants
# all customer threads marked as resolved automatically.
# Params: none.
class Kanban::Automations::Actions::ResolveConversation < Kanban::Automations::Actions::Base
  private

  def perform!
    task.conversations
        .where.not(status: Conversation.statuses[:resolved])
        .find_each { |conversation| conversation.update!(status: :resolved) }
  end
end
