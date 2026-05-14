class CreateKanbanTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :kanban_tasks do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :funnel, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :funnel_stage, null: false, foreign_key: { on_delete: :restrict }, index: true
      t.string :title, null: false, limit: 255
      t.text :description
      t.integer :priority, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.datetime :start_date
      t.datetime :due_date
      t.bigint :display_id
      t.timestamps
    end

    add_index :kanban_tasks, %i[account_id funnel_id]
    add_index :kanban_tasks, %i[funnel_stage_id position]
    add_index :kanban_tasks, %i[account_id display_id], unique: true, where: 'display_id IS NOT NULL'
    add_index :kanban_tasks, :due_date

    create_table :kanban_task_assignees do |t|
      t.references :kanban_task, null: false, foreign_key: { on_delete: :cascade }, index: { name: 'idx_kanban_task_assignees_on_task' }
      t.references :user, null: false, foreign_key: true, index: true
      t.timestamps
    end
    add_index :kanban_task_assignees, %i[kanban_task_id user_id], unique: true, name: 'idx_kt_assignees_unique'

    create_table :kanban_task_labels do |t|
      t.references :kanban_task, null: false, foreign_key: { on_delete: :cascade }, index: { name: 'idx_kanban_task_labels_on_task' }
      t.references :label, null: false, foreign_key: true, index: true
      t.timestamps
    end
    add_index :kanban_task_labels, %i[kanban_task_id label_id], unique: true, name: 'idx_kt_labels_unique'

    create_table :kanban_task_conversations do |t|
      t.references :kanban_task, null: false, foreign_key: { on_delete: :cascade }, index: { name: 'idx_kt_conv_on_task' }
      t.references :conversation, null: false, foreign_key: true, index: true
      t.timestamps
    end
    add_index :kanban_task_conversations, %i[kanban_task_id conversation_id], unique: true, name: 'idx_kt_conversations_unique'

    create_table :kanban_task_contacts do |t|
      t.references :kanban_task, null: false, foreign_key: { on_delete: :cascade }, index: { name: 'idx_kt_contact_on_task' }
      t.references :contact, null: false, foreign_key: true, index: true
      t.timestamps
    end
    add_index :kanban_task_contacts, %i[kanban_task_id contact_id], unique: true, name: 'idx_kt_contacts_unique'
  end
end
