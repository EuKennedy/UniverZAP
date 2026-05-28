class CreateTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :tasks do |t|
      t.references :account, null: false, foreign_key: true, index: true
      # Creator can be nil for system-generated tasks (future feature),
      # but the controllers always populate it from Current.user.
      t.references :created_by_user, foreign_key: { to_table: :users }
      # Account-scoped sequence assigned in #before_create — gives
      # operators a friendly identifier (`#42`) decoupled from the global
      # PK so display in the UI / search / urls is stable.
      t.bigint :display_id

      t.string :title, null: false, limit: 255
      # Description is rich-text JSON (e.g. ProseMirror/Tiptap doc shape)
      # so the dashboard can store inline formatting without dragging in
      # a separate rich-text concern. Empty default keeps payloads sane.
      t.jsonb :description, null: false, default: {}

      t.integer :status, null: false, default: 0
      t.integer :urgency, null: false, default: 0

      t.datetime :due_date
      t.datetime :completed_at

      # Per-task opt-out for the assignment notification flow. Defaults
      # to ON so the common case (notify the assignee) is automatic.
      t.boolean :notify_assignees, null: false, default: true

      t.jsonb :custom_attributes, null: false, default: {}
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    # Hot paths covered explicitly: list-by-status (dashboard tabs),
    # overdue scan (due_date range), urgency filtering on the board.
    add_index :tasks, [:account_id, :status]
    add_index :tasks, [:account_id, :due_date]
    add_index :tasks, [:account_id, :urgency]
    add_index :tasks, :display_id

    create_table :task_assignees do |t|
      t.references :task, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.datetime :notified_at
      t.timestamps
    end

    add_index :task_assignees, [:task_id, :user_id], unique: true

    create_table :task_comments do |t|
      t.references :task, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      # Same rich-text JSON shape as Task#description so the renderer
      # treats them interchangeably on the dashboard.
      t.jsonb :body, null: false, default: {}
      t.datetime :edited_at
      t.timestamps
    end

    create_table :task_activities do |t|
      t.references :task, null: false, foreign_key: true, index: true
      # NULL for system-emitted activities ("scheduler marked overdue").
      t.references :user, foreign_key: { to_table: :users }
      t.string :action, null: false, limit: 64
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end

    add_index :task_activities, [:task_id, :created_at]
  end
end
