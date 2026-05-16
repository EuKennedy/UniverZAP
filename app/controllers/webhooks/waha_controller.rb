class Webhooks::WahaController < ActionController::API
  # WAHA pushes JSON events. We identify the inbox by the session name in the payload,
  # not by the URL slug, so the route is intentionally simple.
  def process_payload
    Webhooks::WahaEventsJob.perform_later(payload_params)
    head :ok
  rescue StandardError => e
    Rails.logger.error("[WAHA webhook] failed to enqueue: #{e.message}")
    head :ok
  end

  private

  def payload_params
    params.except(:controller, :action, :session_name).to_unsafe_hash
  end
end
