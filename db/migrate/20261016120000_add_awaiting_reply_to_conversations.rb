class AddAwaitingReplyToConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  BATCH_SIZE = 5_000

  def up
    add_column :conversations, :awaiting_reply, :boolean, default: false, null: false unless column_exists?(:conversations, :awaiting_reply)

    # The entrypoint migrates under the app's 14s statement_timeout; a batch
    # that crosses it would leave the deploy restarting in a loop.
    execute 'SET statement_timeout = 0'
    backfill
  end

  def down
    remove_column :conversations, :awaiting_reply, if_exists: true
  end

  private

  # A conversation awaits our reply when its latest incoming/outgoing message
  # (not a private note) came from the contact — the rule
  # Message#set_conversation_activity keeps from now on. Each batch reads the
  # messages of a conversation id range through the conversation_id index;
  # MAX(id) is re-read so conversations created meanwhile are covered too.
  def backfill
    start = 0
    while start < select_value('SELECT MAX(id) FROM conversations').to_i
      execute <<~SQL.squish
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
      start += BATCH_SIZE
    end
  end
end
