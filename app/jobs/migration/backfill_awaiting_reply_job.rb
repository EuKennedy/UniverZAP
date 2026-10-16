# Fills conversations.awaiting_reply for conversations that existed before the
# column did. It runs here, not in the migration, because the entrypoint
# migrates before Puma starts: reading every message there kept the rails
# container off the healthcheck and took production down.
#
# Batches walk conversation ids, each in its own short transaction with its own
# timeout, so a big account never needs one long statement. Re-running is safe:
# only rows still false are touched.
class Migration::BackfillAwaitingReplyJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 1_000

  def perform
    max_id = Conversation.maximum(:id).to_i
    (0...max_id).step(BATCH_SIZE) { |start| backfill_batch(start) }
  end

  private

  # A conversation awaits our reply when its latest incoming/outgoing message
  # (not a private note) came from the contact — the rule
  # Message#set_conversation_activity keeps for new messages.
  def backfill_batch(start)
    Conversation.transaction do
      Conversation.connection.execute("SET LOCAL statement_timeout = '120s'")
      Conversation.connection.execute(<<~SQL.squish)
        UPDATE conversations c
        SET awaiting_reply = true
        FROM (
          SELECT DISTINCT ON (m.conversation_id) m.conversation_id, m.message_type
          FROM messages m
          WHERE m.conversation_id > #{start} AND m.conversation_id <= #{start + BATCH_SIZE}
            AND m.message_type IN (0, 1) AND m.private = false
          ORDER BY m.conversation_id, m.id DESC
        ) last_message
        WHERE last_message.conversation_id = c.id AND last_message.message_type = 0 AND c.awaiting_reply = false
      SQL
    end
  end
end
