class CreateTaskViews < ActiveRecord::Migration[7.1]
  # Saved-filter "views" for the Tasks module. Each row freezes a
  # filter combination (status/urgency/scope/etc.) under a friendly
  # name so operators can flip between them with one click. `user_id`
  # is nullable on purpose: NULL means "shared / team view" visible
  # to the whole account.
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def change
    create_table :task_views do |t|
      t.references :account, null: false, foreign_key: true, index: true
      # NULL = shared/team view, owned by the account itself. Only
      # admins (or the original creator) can edit it.
      t.references :user, foreign_key: true

      t.string :name, null: false, limit: 120
      # Free-form filter blob mirroring `Tasks::Finder` keys —
      # scope/status/urgency/assignee_id/due_before/q. Stored as
      # jsonb so future filter dimensions don't require a migration.
      t.jsonb :filters, null: false, default: {}

      t.integer :position, null: false, default: 0
      # When true, this view is auto-applied when the user opens
      # `/tasks` with no explicit scope. At most one per (account,
      # user) tuple is enforced at the model layer.
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end

    add_index :task_views, [:account_id, :user_id]
    add_index :task_views, [:account_id, :position]
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
end
