# Once a day, the safety net for what a webhook did not deliver: WooCommerce
# does not resend a failed delivery, and after a few failures in a row it
# turns the webhook off (a deploy here can be enough). Light on the store: it
# reads the two webhooks, switches back on one that went off and imports only
# the orders changed since the last sync. A store still importing its history
# (never synced) is left alone.
class Woocommerce::PollAllJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    StoreConnection.where(platform: 'woocommerce').where.not(last_synced_at: nil).find_each do |connection|
      Woocommerce::ConnectService.new(connection.account).ensure_webhooks
      since = [connection.last_synced_at, 1.day.ago].min - 1.hour
      Woocommerce::SyncJob.perform_later(connection.id, since.iso8601, silent: false)
    rescue Woocommerce::Client::Error => e
      connection.update!(status: :failing, last_error: e.message.truncate(250))
    end
  end
end
