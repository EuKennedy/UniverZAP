# Reads orders from the store one page per job; each page queues the next, so
# a store with years of orders never holds a worker for long, a page that
# fails is retried on its own and the import goes on from where it stopped.
# Two callers:
#   - the whole history, once, right after connecting (silent: old orders do
#     not touch today's conversations);
#   - a catch-up from a date (the daily check and "Sincronizar agora"), newest
#     first, until an order older than the date shows up.
# Between those the store pushes every new or changed order by webhook, so
# the API is not read again.
class Woocommerce::SyncJob < ApplicationJob
  queue_as :low

  MAX_PAGES = 2000
  # Breathing room between pages, so the import does not weigh on the store.
  PAUSE = 2.seconds

  retry_on Woocommerce::Client::Unavailable, wait: 1.minute, attempts: 5 do |job, error|
    StoreConnection.find_by(id: job.arguments.first)&.update!(status: :failing, last_error: error.message.truncate(250))
  end

  def perform(connection_id, since = nil, silent: true, page: 1, started_at: nil)
    connection = StoreConnection.find_by(id: connection_id)
    return if connection.nil?

    started_at ||= Time.current.iso8601
    orders = client(connection).orders(page: page, modified_after: since.present? ? Time.zone.parse(since) : nil)
    orders.each { |payload| Woocommerce::OrderImporter.new(connection, payload, silent: silent).perform }

    if more?(orders, since) && page < MAX_PAGES
      self.class.set(wait: PAUSE).perform_later(connection_id, since, silent: silent, page: page + 1, started_at: started_at)
    else
      connection.update!(last_synced_at: Time.zone.parse(started_at), status: :connected, last_error: nil)
    end
  rescue Woocommerce::Client::Unavailable
    raise
  rescue Woocommerce::Client::Error => e
    connection&.update!(status: :failing, last_error: e.message.truncate(250))
  end

  private

  def client(connection)
    Woocommerce::Client.new(store_url: connection.store_url, consumer_key: connection.consumer_key,
                            consumer_secret: connection.consumer_secret)
  end

  # A full page may have more behind it. In a catch-up the pages go newest
  # first, so an order older than the date means the rest are older too.
  def more?(orders, since)
    return false if orders.size < Woocommerce::Client::PAGE_SIZE
    return true if since.blank?

    oldest = orders.filter_map { |payload| payload['date_modified_gmt'].presence }.min
    oldest.nil? || Time.zone.parse("#{oldest}Z") >= Time.zone.parse(since)
  end
end
