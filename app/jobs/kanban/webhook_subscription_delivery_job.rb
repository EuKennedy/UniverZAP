# Outbound delivery worker for `KanbanWebhookSubscription`. Signs the
# body with HMAC-SHA256 using the subscription's secret so receivers
# (n8n, Stripe-style verifiers) can verify authenticity:
#
#   HMAC-SHA256(secret, body) → hex digest
#   sent in header `X-UniverZAP-Signature: sha256=<hex>`
#
# Retries on transient failures (5xx, network) via Sidekiq's default
# exponential backoff. 4xx responses don't retry — they signal a config
# bug on the receiver that more attempts can't fix.
class Kanban::WebhookSubscriptionDeliveryJob < ApplicationJob
  queue_as :default

  retry_on Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, HTTParty::Error,
           wait: :exponentially_longer, attempts: 6

  TIMEOUT_SECONDS = 10
  SIGNATURE_HEADER = 'X-UniverZAP-Signature'.freeze
  EVENT_HEADER     = 'X-UniverZAP-Event'.freeze
  ID_HEADER        = 'X-UniverZAP-Delivery-Id'.freeze

  def perform(subscription_id, event, payload)
    subscription = KanbanWebhookSubscription.find_by(id: subscription_id)
    return if subscription.nil? || !subscription.active?

    body = payload.is_a?(String) ? payload : payload.to_json
    response = post(subscription, event, body)
    return handle_success(subscription) if (200..299).cover?(response.code.to_i)

    handle_failure(subscription, response)
  end

  private

  def post(subscription, event, body)
    HTTParty.post(
      subscription.url,
      body: body,
      headers: {
        'Content-Type'      => 'application/json',
        EVENT_HEADER        => event,
        ID_HEADER           => SecureRandom.uuid,
        SIGNATURE_HEADER    => "sha256=#{sign(subscription.secret, body)}"
      },
      timeout: TIMEOUT_SECONDS
    )
  end

  def sign(secret, body)
    OpenSSL::HMAC.hexdigest('SHA256', secret.to_s, body.to_s)
  end

  def handle_success(subscription)
    subscription.track_delivery_success!
  end

  def handle_failure(subscription, response)
    msg = "status=#{response.code}"
    subscription.track_delivery_failure!(msg)
    # Retry only on 5xx — 4xx is a config bug the receiver must fix.
    raise HTTParty::Error, msg if response.code.to_i >= 500
  end
end
