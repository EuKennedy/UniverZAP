class AddTestModeToChatflows < ActiveRecord::Migration[7.1]
  def change
    add_column :chatflows, :test_mode, :boolean, default: false, null: false unless column_exists?(:chatflows, :test_mode)
    add_column :chatflows, :test_phone, :string unless column_exists?(:chatflows, :test_phone)
  end
end
