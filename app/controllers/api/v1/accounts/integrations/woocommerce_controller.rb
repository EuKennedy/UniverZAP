# UniverZAP: the workspace's WooCommerce store. Only e-commerce workspaces have
# it. Admins connect, resync and disconnect; any agent reads a contact's orders
# for the customer sheet, straight from store_orders (the store is never asked
# while someone opens a conversation). The keys never come back out: show
# returns the store URL, the status and the counters.
class Api::V1::Accounts::Integrations::WoocommerceController < Api::V1::Accounts::BaseController
  ORDERS_PER_PAGE = 10

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

    # Never synced means the history import did not finish: run it again
    # (orders already stored are skipped). Otherwise catch up from the last sync.
    since = connection.last_synced_at && (connection.last_synced_at - 5.minutes)
    Woocommerce::SyncJob.perform_later(connection.id, since&.iso8601, silent: since.nil?)
    head :accepted
  end

  def destroy
    Woocommerce::ConnectService.new(Current.account).disconnect
    head :no_content
  end

  # The whole history, a page at a time, newest first.
  def orders
    account = Current.account
    contact = account.contacts.find(params[:contact_id])
    scope = account.store_orders.where(contact: contact).recent_first
    render json: {
      connected: account.store_connection.present?,
      store_name: store_name(account.store_connection),
      customer: scope.first&.slice(:customer_name, :customer_email, :customer_phone),
      metrics: account.store_orders.metrics_for(contact)
    }.merge(orders_page(scope))
  end

  private

  def ensure_store_vertical
    head :not_found unless VerticalProfile.for(Current.account).store_connector?
  end

  def orders_page(scope)
    page = [params[:page].to_i, 1].max
    orders = scope.offset((page - 1) * ORDERS_PER_PAGE).limit(ORDERS_PER_PAGE + 1).to_a
    { orders: orders.first(ORDERS_PER_PAGE).map { |order| order_json(order) }, has_more: orders.size > ORDERS_PER_PAGE }
  end

  def store_name(connection)
    connection && URI.parse(connection.store_url).host.to_s.delete_prefix('www.')
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
