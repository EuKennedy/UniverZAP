# LGPD §8: shipped Sentry config used to default-pii everything. Replaced
# with a recursive scrubber that redacts known secret keys and runs every
# string through PII regexes (email / phone / CPF / CNPJ) before the event
# leaves the process. Default PII is now off so request headers / IPs are
# only included when the redactor approves them.
if ENV['SENTRY_DSN'].present?
  SENTRY_SENSITIVE_KEYS = %w[
    password new_password old_password password_confirmation password_hash
    token access_token refresh_token auth_token jwt
    api_key apikey secret jwt_secret webhook_secret encryption_key
    authorization cookie session
    credit_card cvc cvv card_number
    cpf cnpj rg ssn
  ].freeze

  SENTRY_PII_PATTERNS = [
    [/[\w.+\-]+@[\w\-]+\.[\w.\-]+/i, '[REDACTED_EMAIL]'],
    [/\b\d{2,3}\s?9?\d{4}-?\d{4}\b/, '[REDACTED_PHONE]'],
    [/\b\d{3}\.\d{3}\.\d{3}-\d{2}\b/, '[REDACTED_CPF]'],
    [/\b\d{2}\.\d{3}\.\d{3}\/\d{4}-\d{2}\b/, '[REDACTED_CNPJ]']
  ].freeze

  def sentry_redact_string(value)
    return value unless value.is_a?(String)

    SENTRY_PII_PATTERNS.reduce(value) do |acc, (pattern, replacement)|
      acc.gsub(pattern, replacement)
    end
  end

  def sentry_scrub(value, depth = 0)
    return value if depth > 5

    case value
    when String then sentry_redact_string(value)
    when Array then value.map { |item| sentry_scrub(item, depth + 1) }
    when Hash
      value.each_with_object({}) do |(key, val), acc|
        acc[key] = if SENTRY_SENSITIVE_KEYS.include?(key.to_s.downcase)
                     '[Filtered]'
                   else
                     sentry_scrub(val, depth + 1)
                   end
      end
    else value
    end
  end

  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.enabled_environments = %w[staging production]
    config.traces_sample_rate = 0.1 if ENV['ENABLE_SENTRY_TRANSACTIONS']
    config.excluded_exceptions += ['Rack::Timeout::RequestTimeoutException', 'MutexApplicationJob::LockAcquisitionError']

    # LGPD: never send default PII (IP, headers, etc) — the before_send
    # below scrubs anything PII that slips into a breadcrumb or extra.
    config.send_default_pii = false

    config.before_send = lambda do |event, _hint|
      event.request&.tap do |req|
        req.headers&.tap do |headers|
          %w[Cookie cookie Authorization authorization X-Api-Key x-api-key].each do |header|
            headers[header] = '[Filtered]' if headers.key?(header)
          end
        end
        req.data = sentry_scrub(req.data) if req.data
      end

      event.tap do |evt|
        evt.message = sentry_redact_string(evt.message) if evt.message
        evt.breadcrumbs&.each do |breadcrumb|
          breadcrumb.message = sentry_redact_string(breadcrumb.message) if breadcrumb.message
          breadcrumb.data = sentry_scrub(breadcrumb.data) if breadcrumb.data
        end
        evt.extra = sentry_scrub(evt.extra) if evt.extra
        evt.contexts = sentry_scrub(evt.contexts) if evt.contexts
      end

      event.exception&.values&.each do |exc|
        exc.value = sentry_redact_string(exc.value) if exc.value
      end

      event.user&.tap do |user|
        user.delete(:email)
        user.delete(:username)
        user.delete(:ip_address)
      end

      event
    end
  end
end
