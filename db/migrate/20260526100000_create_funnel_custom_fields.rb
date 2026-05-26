class CreateFunnelCustomFields < ActiveRecord::Migration[7.1]
  def change
    create_funnel_custom_fields_table
    create_kanban_task_custom_values_table
  end

  private

  def create_funnel_custom_fields_table
    create_table :funnel_custom_fields do |t|
      t.references :funnel, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :name, null: false
      t.integer :field_type, null: false, default: 0
      t.jsonb :options, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.boolean :required, null: false, default: false
      t.timestamps
    end
  end

  def create_kanban_task_custom_values_table
    create_table :kanban_task_custom_values do |t|
      t.references :kanban_task, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :funnel_custom_field, null: false, foreign_key: { on_delete: :cascade }, index: { name: 'idx_custom_values_on_field_id' }
      t.text :value
      t.timestamps
      t.index %i[kanban_task_id funnel_custom_field_id],
              unique: true,
              name: 'idx_custom_values_unique_per_task_field'
    end
  end
end
