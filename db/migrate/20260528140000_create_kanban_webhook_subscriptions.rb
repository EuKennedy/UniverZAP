class CreateKanbanWebhookSubscriptions < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_webhook_subscriptions do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.string :name, null: false, limit: 120
      # Target URL (must be https in production via ENV gate). Length cap
      # so a runaway integration can't fill the table with multi-MB URLs.
      t.string :url, null: false, limit: 2048
      # Catalogue of events the subscription listens to. Empty array
      # means "all events". Keep as JSONB so we can add events without
      # a migration.
      t.jsonb :events, null: false, default: []
      # 32-byte secret used to sign each delivery's body with HMAC-SHA256.
      # Stored as plaintext on purpose — the operator needs to copy it
      # into their verifier (n8n, custom endpoint, etc.). Encryption at
      # rest is handled by the DB volume, not by us re-rolling crypto.
      t.string :secret, null: false, limit: 128
      t.boolean :active, null: false, default: true
      t.integer :delivery_count, null: false, default: 0
      t.integer :failure_count, null: false, default: 0
      t.datetime :last_delivered_at
      t.datetime :last_failed_at
      t.string :last_error_message, limit: 500
      t.timestamps
    end

    add_index :kanban_webhook_subscriptions, [:account_id, :active]
  end
end
