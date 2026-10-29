# Connecting a WooCommerce store, the way SAK does it but without a plugin:
# probe the keys, save them (encrypted), ask the store to send order webhooks
# here (signed with a secret only this account has) and import the store's
# whole order history in the background. From then on the webhooks keep the
# orders current. Reconnecting replaces the keys and the webhooks;
# disconnecting removes the webhooks from the store too.
class Woocommerce::ConnectService
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
    Woocommerce::SyncJob.perform_later(connection.id)
    connection
  end

  # The webhooks are what spare the API, so the daily check makes sure both
  # still exist and are on. WooCommerce switches one off after repeated
  # failed deliveries; a missing one is registered again.
  def ensure_webhooks
    connection = @account.store_connection
    return reregister_webhooks(connection) if connection.webhook_ids.size < Woocommerce::Client::WEBHOOK_TOPICS.size

    connection.webhook_ids.map { |id| client(connection).webhook(id) }
              .reject { |hook| hook['status'] == 'active' }
              .each { |hook| client(connection).activate_webhook(hook['id']) }
  rescue Woocommerce::Client::NotFound
    reregister_webhooks(connection)
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

  def reregister_webhooks(connection)
    remove_webhooks(connection)
    connection.update!(webhook_ids: register_webhooks(connection))
  end

  # Best effort: the store may already be gone or the keys revoked.
  def remove_webhooks(connection)
    connection.webhook_ids.each { |id| client(connection).delete_webhook(id) }
  rescue Woocommerce::Client::Error => e
    Rails.logger.warn("[woocommerce] account=#{@account.id} could not remove webhooks: #{e.message}")
  end
end
