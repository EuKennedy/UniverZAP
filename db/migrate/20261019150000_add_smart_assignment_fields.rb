class AddSmartAssignmentFields < ActiveRecord::Migration[7.1]
  def change
    add_column :assignment_policies, :sticky_contact, :boolean, default: false, null: false
    add_column :assignment_policies, :require_online, :boolean, default: true, null: false
    add_column :inbox_members, :assignment_capacity, :integer
  end
end
