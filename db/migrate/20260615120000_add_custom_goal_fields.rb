class AddCustomGoalFields < ActiveRecord::Migration[7.1]
  def change
    # Goals are no longer sales-only. `name` is the custom label (e.g.
    # "Depoimentos"), `unit` decides how progress is rendered (currency vs a
    # plain count) and `category` is the slug that ties records to this goal.
    add_column :sales_goals, :name, :string, null: false, default: 'Vendas'
    add_column :sales_goals, :unit, :integer, null: false, default: 0
    add_column :sales_goals, :category, :string, null: false, default: 'sales'
    add_index :sales_goals, [:account_id, :category]

    # Records carry the same `category` so a goal only sums what belongs to it.
    # `order_number` and `paid_at` capture the sale's invoice + payment date.
    add_column :sale_records, :category, :string, null: false, default: 'sales'
    add_column :sale_records, :order_number, :string
    add_column :sale_records, :paid_at, :datetime
    add_index :sale_records, [:account_id, :user_id, :category, :recorded_at],
              name: 'index_sale_records_on_account_user_category_recorded'

    # Custom (count) goals can be registered without a contact, so the FK must
    # tolerate a null contact.
    change_column_null :sale_records, :contact_id, true
  end
end
