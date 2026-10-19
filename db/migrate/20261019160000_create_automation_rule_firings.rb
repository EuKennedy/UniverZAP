class CreateAutomationRuleFirings < ActiveRecord::Migration[7.1]
  def change
    create_table :automation_rule_firings do |t|
      t.references :automation_rule, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.string :dedupe_key, null: false
      t.datetime :created_at, null: false
    end
    add_index :automation_rule_firings, [:automation_rule_id, :conversation_id, :dedupe_key],
              unique: true, name: 'index_automation_rule_firings_unique'
  end
end
