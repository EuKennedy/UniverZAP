# Order webhooks from a connected WooCommerce store. The token in the URL says
# which store; the body must be signed with that store's secret
# (X-WC-Webhook-Signature = base64 HMAC-SHA256 of the raw body). WooCommerce
# pings the URL once when the webhook is created, with no signature and a
# form body — answered 200 so the store keeps the webhook active.
class Webhooks::WoocommerceController < ActionController::API
  def create
    connection = StoreConnection.find_by(webhook_token: params[:token])
    return head :not_found if connection.nil?
    return head :ok if ping?
    return head :unauthorized unless valid_signature?(connection)

    Woocommerce::WebhookJob.perform_later(connection.id, request.raw_post)
    head :ok
  end

  private

  def ping?
    request.headers['X-WC-Webhook-Signature'].blank? && request.raw_post.start_with?('webhook_id=')
  end

  def valid_signature?(connection)
    signature = request.headers['X-WC-Webhook-Signature'].to_s
    expected = Base64.strict_encode64(OpenSSL::HMAC.digest('sha256', connection.webhook_secret, request.raw_post))
    signature.present? && ActiveSupport::SecurityUtils.secure_compare(signature, expected)
  end
end
