class AddSubtasksAndEstimateToKanbanTasks < ActiveRecord::Migration[7.1]
  def change
    add_reference :kanban_tasks, :parent_task,
                  null: true,
                  foreign_key: { to_table: :kanban_tasks, on_delete: :cascade },
                  index: true

    add_column :kanban_tasks, :estimate_minutes, :integer
    add_column :kanban_tasks, :completed_at, :datetime

    add_index :kanban_tasks, :completed_at
  end
end
