class AddAwaitingReplyToConversations < ActiveRecord::Migration[7.1]
  # Only the column, which is instant on Postgres 11+. Filling it reads every
  # message, so it runs in Sidekiq (Migration::BackfillAwaitingReplyJob): the
  # entrypoint migrates before Puma starts, and a long migration here keeps the
  # rails container off the healthcheck.
  def up
    add_column :conversations, :awaiting_reply, :boolean, default: false, null: false unless column_exists?(:conversations, :awaiting_reply)

    Migration::BackfillAwaitingReplyJob.perform_later
  end

  def down
    remove_column :conversations, :awaiting_reply, if_exists: true
  end
end
