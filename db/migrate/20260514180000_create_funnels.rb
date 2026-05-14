class CreateFunnels < ActiveRecord::Migration[7.1]
  def change
    create_table :funnels do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false, limit: 120
      t.text :description
      t.integer :position, null: false, default: 0
      t.jsonb :automation_settings, null: false, default: {}
      t.timestamps
    end

    add_index :funnels, %i[account_id position]
    add_index :funnels, %i[account_id name]

    create_table :funnel_inboxes do |t|
      t.references :funnel, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :inbox, null: false, foreign_key: true, index: true
      t.timestamps
    end
    add_index :funnel_inboxes, %i[funnel_id inbox_id], unique: true

    create_table :funnel_agents do |t|
      t.references :funnel, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.timestamps
    end
    add_index :funnel_agents, %i[funnel_id user_id], unique: true
  end
end
