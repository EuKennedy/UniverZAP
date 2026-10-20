class AddIsStatusBroadcastToConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :conversations, :is_status_broadcast, :boolean, default: false, null: false unless column_exists?(:conversations, :is_status_broadcast)

    add_index :conversations, %i[account_id is_status_broadcast], algorithm: :concurrently, if_not_exists: true

    # WhatsApp delivers the statuses contacts post through one chat,
    # "status@broadcast" — the WAHA connector uses it as the contact identifier.
    execute <<~SQL.squish
      UPDATE conversations c
      SET is_status_broadcast = true
      FROM contacts ct
      WHERE c.contact_id = ct.id
        AND ct.identifier = 'status@broadcast'
        AND c.is_status_broadcast = false
    SQL
  end

  def down
    remove_index :conversations, %i[account_id is_status_broadcast], if_exists: true
    remove_column :conversations, :is_status_broadcast, if_exists: true
  end
end
