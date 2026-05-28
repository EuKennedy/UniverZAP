class CreateKanbanAutomations < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_automations do |t|
      t.references :account, null: false, foreign_key: true, index: true
      # NULL = account-wide rule (fires for any funnel on the account).
      # NOT NULL = scoped to that funnel — most rules live here.
      t.references :funnel, null: true, foreign_key: true, index: true
      t.string :name, null: false, limit: 120
      t.text :description
      t.string :event_name, null: false, limit: 64
      t.jsonb :conditions, null: false, default: {}
      # Array of `{ type:, params: {...} }` hashes executed in order.
      t.jsonb :actions, null: false, default: []
      t.boolean :active, null: false, default: true
      t.integer :run_count, null: false, default: 0
      t.datetime :last_run_at
      t.datetime :last_error_at
      t.string :last_error_message, limit: 500
      t.timestamps
    end

    # Hot path: dispatcher fetches `where(account_id:, event_name:, active: true)`
    # on every event. Composite index covers it without touching the table.
    add_index :kanban_automations, [:account_id, :event_name, :active]
    # Secondary: funnel-scoped lookups when an event carries a funnel context.
    add_index :kanban_automations, [:funnel_id, :event_name, :active]
  end
end
