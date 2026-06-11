class AddIsGroupToConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :conversations, :is_group, :boolean, default: false, null: false unless column_exists?(:conversations, :is_group)

    add_index :conversations, %i[account_id is_group], algorithm: :concurrently, if_not_exists: true

    # Backfill: a conversation is a WhatsApp group when its contact identifier
    # ends with "@g.us" (the WhatsApp group jid format, e.g. 1203...@g.us).
    execute <<~SQL.squish
      UPDATE conversations c
      SET is_group = true
      FROM contacts ct
      WHERE c.contact_id = ct.id
        AND ct.identifier LIKE '%@g.us'
        AND c.is_group = false
    SQL
  end

  def down
    remove_index :conversations, %i[account_id is_group], if_exists: true
    remove_column :conversations, :is_group, if_exists: true
  end
end
