# Fire-and-forget HTTP delivery for the `webhook` automation action.
# Sidekiq retries handle backoff; we let the default exponential
# retry kick in (~30 retries over ~20 days). Anything still failing
# after that lands in the dead set for manual replay.
class Kanban::Automations::WebhookDeliveryJob < ApplicationJob
  queue_as :default

  # Retry on network blips and 5xx — let Sidekiq's default backoff
  # handle the cadence (10s, 20s, 40s, ... up to ~21 days).
  retry_on Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, HTTParty::Error,
           wait: :exponentially_longer, attempts: 5

  TIMEOUT_SECONDS = 10

  def perform(url:, method:, headers:, payload:)
    response = HTTParty.send(
      method.downcase.to_sym,
      url,
      body: payload.to_json,
      headers: { 'Content-Type' => 'application/json' }.merge(headers || {}),
      timeout: TIMEOUT_SECONDS
    )
    return if (200..299).cover?(response.code.to_i)

    Rails.logger.warn(
      "[Kanban automation] webhook url=#{url} status=#{response.code} attempt=#{executions}"
    )
    # Raising re-enters the retry loop on 5xx; 4xx falls through (the
    # operator likely misconfigured the integration and retries won't
    # help).
    raise HTTParty::Error, "status=#{response.code}" if response.code.to_i >= 500
  end
end
