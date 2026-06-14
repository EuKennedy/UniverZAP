class CreateSalesGoals < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_goals do |t|
      t.references :account, null: false, index: true, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :period, null: false, default: 0
      t.decimal :target_amount, precision: 12, scale: 2, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :sales_goals, [:account_id, :user_id]

    create_table :sale_records do |t|
      t.references :account, null: false, index: true, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.decimal :amount, precision: 12, scale: 2, null: false, default: 0
      t.datetime :recorded_at, null: false

      t.timestamps
    end

    add_index :sale_records, [:account_id, :user_id, :recorded_at]
  end
end
