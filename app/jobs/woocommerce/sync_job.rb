# Pulls orders modified since `since` page by page. Two callers:
#   - the first import after connecting (90 days back, silent: old orders do
#     not touch today's conversations);
#   - the poller, every 15 minutes, from the last sync — the safety net for a
#     webhook the store failed to deliver. Those are recent, so they relabel.
class Woocommerce::SyncJob < ApplicationJob
  queue_as :low

  MAX_PAGES = 200

  def perform(connection_id, since = nil, silent: true)
    connection = StoreConnection.find_by(id: connection_id)
    return if connection.nil?

    started = Time.current
    import_pages(connection, since.present? ? Time.zone.parse(since) : nil, silent)
    connection.update!(last_synced_at: started, status: :connected, last_error: nil)
  rescue Woocommerce::Client::Error => e
    connection&.update!(status: :failing, last_error: e.message.truncate(250))
  end

  private

  def import_pages(connection, since, silent)
    client = Woocommerce::Client.new(store_url: connection.store_url, consumer_key: connection.consumer_key,
                                     consumer_secret: connection.consumer_secret)
    (1..MAX_PAGES).each do |page|
      orders = client.orders(page: page, modified_after: since)
      orders.each { |payload| Woocommerce::OrderImporter.new(connection, payload, silent: silent).perform }
      break if orders.size < Woocommerce::Client::PAGE_SIZE
    end
  end
end
