class AddPinnedAtToConversations < ActiveRecord::Migration[7.1]
  # Pinned conversations float to the very top of the inbox list regardless
  # of the current sort. Storing the timestamp (instead of a bool) lets us
  # order multiple pinned chats among themselves by most-recently-pinned
  # without a second column. NULL = not pinned, the default state.
  def change
    add_column :conversations, :pinned_at, :datetime
    add_index :conversations, :pinned_at
  end
end
