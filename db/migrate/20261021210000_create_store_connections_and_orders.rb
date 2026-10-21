class CreateStoreConnectionsAndOrders < ActiveRecord::Migration[7.1]
  def change
    create_store_connections
    create_store_orders
  end

  private

  def create_store_connections
    create_table :store_connections do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :platform, null: false, default: 'woocommerce'
      t.string :store_url, null: false
      t.string :consumer_key, null: false
      t.string :consumer_secret, null: false
      t.string :webhook_secret, null: false
      t.string :webhook_token, null: false, index: { unique: true }
      t.jsonb :webhook_ids, null: false, default: []
      t.integer :status, null: false, default: 0
      t.string :last_error
      t.datetime :last_synced_at
      t.timestamps
    end
  end

  def create_store_orders # rubocop:disable Metrics/MethodLength
    create_table :store_orders do |t|
      t.references :account, null: false, foreign_key: true
      t.references :store_connection, null: false, foreign_key: true
      t.references :contact, foreign_key: { on_delete: :nullify }
      t.string :external_id, null: false
      t.string :number
      t.string :status, null: false
      t.string :currency, default: 'BRL'
      t.decimal :total, precision: 12, scale: 2, null: false, default: 0
      t.string :payment_method
      t.string :payment_method_title
      t.string :payment_url
      t.string :customer_name
      t.string :customer_phone
      t.string :customer_email
      t.jsonb :items, null: false, default: []
      t.jsonb :tracking, null: false, default: {}
      t.datetime :placed_at
      t.datetime :paid_at
      t.datetime :store_updated_at
      t.timestamps
    end
    add_index :store_orders, [:store_connection_id, :external_id], unique: true
    add_index :store_orders, [:contact_id, :placed_at]
  end
end
