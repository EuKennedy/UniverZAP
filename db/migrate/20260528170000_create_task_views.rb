class CreateTaskViews < ActiveRecord::Migration[7.1]
  # Saved-filter "views" for the Tasks module. Each row freezes a
  # filter combination (status/urgency/scope/etc.) under a friendly
  # name so operators can flip between them with one click. `user_id`
  # is nullable on purpose: NULL means "shared / team view" visible
  # to the whole account.
  def change
    create_table :task_views do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :user, foreign_key: true

      t.string :name, null: false, limit: 120
      t.jsonb :filters, null: false, default: {}

      t.integer :position, null: false, default: 0
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end

    add_index :task_views, [:account_id, :user_id]
    add_index :task_views, [:account_id, :position]
  end
end
