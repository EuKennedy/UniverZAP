# Fire an outbound HTTP webhook with the task payload. The delivery
# itself happens in a background job so a slow third party never blocks
# the automation executor — failures are retried with exponential
# backoff and recorded on the rule.
#
# Params:
#   url (String, required)  — must be HTTP(S)
#   method (String, default 'POST') — POST | PUT | PATCH
#   headers (Hash, optional) — { 'X-Token' => 'abc' }
#   include (Array<String>, optional) — fields to include from the task
#     payload. Defaults to the full `push_event_data`.
class Kanban::Automations::Actions::Webhook < Kanban::Automations::Actions::Base
  ALLOWED_METHODS = %w[POST PUT PATCH].freeze
  ALLOWED_SCHEMES = %w[http https].freeze

  private

  def perform!
    url = required_param!(:url).to_s
    raise ExecutionError, "url=#{url} must be http(s)" unless valid_url?(url)

    method = (params[:method].to_s.upcase.presence || 'POST')
    raise ExecutionError, "unsupported method=#{method}" unless ALLOWED_METHODS.include?(method)

    payload = build_payload
    headers = (params[:headers].is_a?(Hash) ? params[:headers] : {}).slice(*params[:headers]&.keys.to_a)
    Kanban::Automations::WebhookDeliveryJob.perform_later(
      url: url,
      method: method,
      headers: headers,
      payload: payload
    )
  end

  def valid_url?(url)
    uri = URI.parse(url)
    ALLOWED_SCHEMES.include?(uri.scheme.to_s.downcase) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def build_payload
    base = task.push_event_data.merge(event: event_payload)
    fields = Array(params[:include]).map(&:to_s)
    return base if fields.empty?

    base.slice(*fields)
  end
end
