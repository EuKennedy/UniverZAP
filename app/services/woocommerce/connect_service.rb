# Connecting a WooCommerce store, the way SAK does it but without a plugin:
# probe the keys, save them (encrypted), ask the store to send order webhooks
# here (signed with a secret only this account has) and import the last
# BACKFILL_DAYS of orders in the background. Reconnecting replaces the keys
# and the webhooks; disconnecting removes the webhooks from the store too.
class Woocommerce::ConnectService
  BACKFILL_DAYS = 90

  def initialize(account)
    @account = account
  end

  def connect(store_url:, consumer_key:, consumer_secret:)
    store_url = store_url.to_s.strip.chomp('/')
    Woocommerce::Client.new(store_url: store_url, consumer_key: consumer_key, consumer_secret: consumer_secret).probe!

    connection = @account.store_connection || @account.build_store_connection
    remove_webhooks(connection) if connection.persisted?
    connection.update!(store_url: store_url, consumer_key: consumer_key, consumer_secret: consumer_secret,
                       status: :connected, last_error: nil, webhook_ids: [])
    connection.update!(webhook_ids: register_webhooks(connection))
    Woocommerce::SyncJob.perform_later(connection.id, BACKFILL_DAYS.days.ago.iso8601)
    connection
  end

  def disconnect
    connection = @account.store_connection
    return if connection.nil?

    remove_webhooks(connection)
    connection.destroy!
  end

  private

  def client(connection)
    Woocommerce::Client.new(store_url: connection.store_url, consumer_key: connection.consumer_key,
                            consumer_secret: connection.consumer_secret)
  end

  def register_webhooks(connection)
    Woocommerce::Client::WEBHOOK_TOPICS.map do |topic|
      client(connection).create_webhook(topic: topic, delivery_url: connection.webhook_url, secret: connection.webhook_secret)['id']
    end
  end

  # Best effort: the store may already be gone or the keys revoked.
  def remove_webhooks(connection)
    connection.webhook_ids.each { |id| client(connection).delete_webhook(id) }
  rescue Woocommerce::Client::Error => e
    Rails.logger.warn("[woocommerce] account=#{@account.id} could not remove webhooks: #{e.message}")
  end
end
