class AddRecurrenceToTasks < ActiveRecord::Migration[7.1]
  # Recurrence support on Task. We materialize each occurrence as a
  # standalone row (rather than a virtual schedule) so the existing
  # list/board/notification/activity flow continues to work without
  # any branching for recurring tasks. The parent row holds the rule
  # and acts as the template.
  def change
    add_column :tasks, :recurrence_rule, :jsonb, default: {}, null: false
    add_column :tasks, :recurrence_parent_id, :bigint
    add_column :tasks, :next_occurrence_at, :datetime

    add_index :tasks, :recurrence_parent_id
    add_index :tasks, :next_occurrence_at
  end
end
