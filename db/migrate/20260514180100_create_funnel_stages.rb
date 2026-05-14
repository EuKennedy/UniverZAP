class CreateFunnelStages < ActiveRecord::Migration[7.1]
  def change
    create_table :funnel_stages do |t|
      t.references :funnel, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :name, null: false, limit: 120
      t.text :description
      t.string :color, null: false, default: '#64748B'
      t.integer :position, null: false, default: 0
      t.integer :status_type, null: false, default: 0
      t.timestamps
    end

    add_index :funnel_stages, %i[funnel_id position]
    add_index :funnel_stages, %i[funnel_id status_type]
  end
end
