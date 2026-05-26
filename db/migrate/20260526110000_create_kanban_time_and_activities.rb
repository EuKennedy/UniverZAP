class CreateKanbanTimeAndActivities < ActiveRecord::Migration[7.1]
  def change
    create_time_entries_table
    create_activities_table
  end

  private

  def create_time_entries_table
    create_table :kanban_task_time_entries do |t|
      t.references :kanban_task, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :duration_seconds
      t.string :note
      t.timestamps
      t.index [:kanban_task_id, :ended_at], name: 'idx_kanban_time_entries_open'
    end
  end

  def create_activities_table
    create_table :kanban_task_activities do |t|
      t.references :kanban_task, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :user, null: true, foreign_key: true, index: true
      t.string :action, null: false
      t.text :summary, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :kanban_task_activities, [:kanban_task_id, :created_at], name: 'idx_kanban_activities_timeline'
  end
end
