class Webhooks::WahaController < ActionController::API
  # WAHA pushes JSON events. We identify the inbox by the session name in the payload,
  # not by the URL slug, so the route is intentionally simple.
  #
  # Because of that the payload alone proves nothing: session names follow
  # u{account}-{slug}, so anyone could post "a customer wrote" and have Athenas
  # answer an arbitrary number from that customer's WhatsApp. With
  # WAHA_WEBHOOK_HMAC_KEY set, WAHA signs every event (X-Webhook-Hmac, sha512
  # HMAC of the raw body) and a wrong signature is refused. Unsigned events
  # still pass until WAHA_WEBHOOK_HMAC_REQUIRED is on, so sessions created
  # before the key keep delivering while `rake waha:sync_webhooks` signs them.
  def process_payload
    return head(:unauthorized) unless authentic?

    Webhooks::WahaEventsJob.perform_later(payload_params)
    head :ok
  rescue StandardError => e
    Rails.logger.error("[WAHA webhook] failed to enqueue: #{e.message}")
    head :ok
  end

  private

  def authentic?
    key = ENV.fetch('WAHA_WEBHOOK_HMAC_KEY', nil)
    return true if key.blank?

    signature = request.headers['X-Webhook-Hmac']
    return unsigned_allowed? if signature.blank?

    valid = ActiveSupport::SecurityUtils.secure_compare(OpenSSL::HMAC.hexdigest('SHA512', key, request.raw_post), signature)
    Rails.logger.warn("[WAHA webhook] rejected: bad signature session=#{params[:session]}") unless valid
    valid
  end

  def unsigned_allowed?
    return true unless ActiveModel::Type::Boolean.new.cast(ENV.fetch('WAHA_WEBHOOK_HMAC_REQUIRED', false))

    Rails.logger.warn("[WAHA webhook] rejected: unsigned session=#{params[:session]}")
    false
  end

  def payload_params
    params.except(:controller, :action, :session_name).to_unsafe_hash
  end
end
