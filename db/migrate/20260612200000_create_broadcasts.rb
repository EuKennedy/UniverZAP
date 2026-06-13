class CreateBroadcasts < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :broadcasts do |t|
      t.references :account, null: false, index: true, foreign_key: true
      t.references :inbox, foreign_key: true
      t.string :name, null: false
      t.string :mode, null: false, default: 'waha'
      t.integer :status, null: false, default: 0
      t.jsonb :message, default: {}
      t.jsonb :audience, default: {}
      t.jsonb :throttle, default: {}
      t.datetime :scheduled_at

      t.timestamps
    end

    create_table :broadcast_recipients do |t|
      t.references :broadcast, null: false, index: true, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.bigint :conversation_id
      t.integer :status, null: false, default: 0
      t.string :error
      t.datetime :sent_at

      t.timestamps
    end

    add_index :broadcast_recipients, [:broadcast_id, :status]
  end
end
