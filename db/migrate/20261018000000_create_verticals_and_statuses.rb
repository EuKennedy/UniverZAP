class CreateVerticalsAndStatuses < ActiveRecord::Migration[7.1]
  def change
    create_table :verticals do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.timestamps
    end
    add_index :verticals, :key, unique: true

    create_table :vertical_statuses do |t|
      t.references :vertical, null: false, foreign_key: true
      t.string :title, null: false
      t.string :color, null: false, default: '#1f93ff'
      t.text :description
      t.boolean :closes_conversation, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_column :labels, :closes_conversation, :boolean, null: false, default: false
  end
end
