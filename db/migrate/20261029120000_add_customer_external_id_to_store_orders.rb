class AddCustomerExternalIdToStoreOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :store_orders, :customer_external_id, :string
    add_index :store_orders, [:store_connection_id, :customer_external_id], name: 'index_store_orders_on_connection_and_customer'
  end
end
