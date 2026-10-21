# UniverZAP: the workspace's WooCommerce store. Only e-commerce workspaces have
# it. Admins connect, resync and disconnect; any agent reads a contact's orders
# for the customer sheet. The keys never come back out: show returns the store
# URL, the status and the counters.
class Api::V1::Accounts::Integrations::WoocommerceController < Api::V1::Accounts::BaseController
  RECENT_ORDERS = 5

  before_action :ensure_store_vertical
  before_action :check_admin_authorization?, only: [:create, :sync, :destroy]

  def show
    render json: connection_json(Current.account.store_connection)
  end

  def create
    keys = params.permit(:store_url, :consumer_key, :consumer_secret).to_h.symbolize_keys
    connection = Woocommerce::ConnectService.new(Current.account).connect(**keys)
    render json: connection_json(connection)
  rescue Woocommerce::Client::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def sync
    connection = Current.account.store_connection
    return head :not_found if connection.nil?

    since = connection.last_synced_at || Woocommerce::ConnectService::BACKFILL_DAYS.days.ago
    Woocommerce::SyncJob.perform_later(connection.id, since.iso8601, silent: false)
    head :accepted
  end

  def destroy
    Woocommerce::ConnectService.new(Current.account).disconnect
    head :no_content
  end

  def orders
    contact = Current.account.contacts.find(params[:contact_id])
    orders = Current.account.store_orders.where(contact: contact).recent_first.limit(RECENT_ORDERS)
    render json: {
      connected: Current.account.store_connection.present?,
      metrics: Current.account.store_orders.metrics_for(contact),
      orders: orders.map { |order| order_json(order) }
    }
  end

  private

  def ensure_store_vertical
    head :not_found unless VerticalProfile.for(Current.account).store_connector?
  end

  def connection_json(connection)
    return { connected: false } if connection.nil?

    {
      connected: true,
      platform: connection.platform,
      store_url: connection.store_url,
      status: connection.status,
      last_error: connection.last_error,
      last_synced_at: connection.last_synced_at,
      orders_count: connection.store_orders.count,
      linked_orders_count: connection.store_orders.where.not(contact_id: nil).count
    }
  end

  def order_json(order)
    order.slice(:id, :number, :status, :currency, :total, :payment_method_title, :payment_url, :items, :tracking, :placed_at, :paid_at)
         .merge(total: order.total.to_f, admin_url: "#{order.store_connection.store_url}/wp-admin/post.php?post=#{order.external_id}&action=edit")
  end
end
