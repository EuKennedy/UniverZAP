class FixTasksDisplayIdIndex < ActiveRecord::Migration[7.1]
  # Original migration shipped a non-composite, non-unique index on
  # `tasks.display_id` so the friendly identifier collided across accounts
  # — multiple tenants could see `#42` referring to different tasks and the
  # lookup planner had no signal to enforce uniqueness per tenant.
  #
  # We replace the global index with a partial unique composite
  # `[account_id, display_id]`, matching the convention used by
  # `kanban_tasks.display_id` (see 20260514180200_create_kanban_tasks.rb:28).
  # The partial WHERE keeps the unique guarantee tolerant of historical rows
  # where `display_id` was never assigned (system-created tasks, future
  # features that defer numbering).
  #
  # Both swaps run inside a single migration so a deploy can never land
  # mid-state with the index missing.
  def change
    remove_index :tasks, :display_id, if_exists: true
    add_index :tasks, %i[account_id display_id],
              unique: true,
              where: 'display_id IS NOT NULL',
              name: 'index_tasks_on_account_id_and_display_id'
  end
end
