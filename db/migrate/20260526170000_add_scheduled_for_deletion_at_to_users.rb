class AddScheduledForDeletionAtToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :scheduled_for_deletion_at, :datetime
    add_index :users, :scheduled_for_deletion_at
  end
end
