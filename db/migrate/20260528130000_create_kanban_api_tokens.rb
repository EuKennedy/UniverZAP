class CreateKanbanApiTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_api_tokens do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :created_by_user, foreign_key: { to_table: :users }
      # Display name + visible prefix help the operator identify tokens
      # in the dashboard without exposing the secret.
      t.string :name, null: false, limit: 120
      t.string :token_prefix, null: false, limit: 32, index: true
      # SHA-256 of the raw token. Raw value is shown ONCE on creation
      # and is unrecoverable afterwards — same pattern Stripe / GitHub
      # use for API keys.
      t.string :token_digest, null: false, limit: 128
      # Array of granted scopes, e.g. ["read:tasks", "write:tasks",
      # "manage:webhooks"]. Empty array = read-only on everything.
      t.jsonb :scopes, null: false, default: []
      t.datetime :expires_at
      t.datetime :last_used_at
      t.string :last_used_ip, limit: 64
      t.datetime :revoked_at
      t.bigint :revoked_by_user_id
      t.timestamps
    end

    add_index :kanban_api_tokens, :token_digest, unique: true
    add_index :kanban_api_tokens, [:account_id, :revoked_at]
  end
end
