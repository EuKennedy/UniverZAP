# Every 15 minutes, catches up each connected store from its last sync, in
# case a webhook never arrived (store offline, plugin blocking outgoing
# requests). Recent orders, so the conversations are updated too.
class Woocommerce::PollAllJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    StoreConnection.where(platform: 'woocommerce').find_each do |connection|
      since = (connection.last_synced_at || 1.hour.ago) - 5.minutes
      Woocommerce::SyncJob.perform_later(connection.id, since.iso8601, silent: false)
    end
  end
end
