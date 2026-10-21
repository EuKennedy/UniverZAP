class AddIsTeamToConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :conversations, :is_team, :boolean, default: false, null: false unless column_exists?(:conversations, :is_team)

    add_index :conversations, %i[account_id is_team], algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :conversations, %i[account_id is_team], if_exists: true
    remove_column :conversations, :is_team, if_exists: true
  end
end
