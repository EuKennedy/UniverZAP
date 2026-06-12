class AddColorToChatflows < ActiveRecord::Migration[7.1]
  def change
    add_column :chatflows, :color, :string, default: '#5FB89F', null: false unless column_exists?(:chatflows, :color)
  end
end
