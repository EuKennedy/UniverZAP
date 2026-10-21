# One order webhook, already authenticated by the controller. Webhooks are
# what makes the conversation follow the order in near real time, so they are
# never silent.
class Woocommerce::WebhookJob < ApplicationJob
  queue_as :default

  def perform(connection_id, raw_body)
    connection = StoreConnection.find_by(id: connection_id)
    payload = JSON.parse(raw_body)
    return if connection.nil? || payload['id'].blank?

    Woocommerce::OrderImporter.new(connection, payload).perform
  end
end
