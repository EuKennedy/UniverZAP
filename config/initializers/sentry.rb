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
    [%r{\b\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}\b}, '[REDACTED_CNPJ]']
  ].freeze

  def sentry_redact_string(value)
    return value unless value.is_a?(String)

    SENTRY_PII_PATTERNS.reduce(value) do |acc, (pattern, replacement)|
      acc.gsub(pattern, replacement)
    end
  end

  def sentry_scrub_hash(value, depth)
    value.each_with_object({}) do |(key, val), acc|
      acc[key] = if SENTRY_SENSITIVE_KEYS.include?(key.to_s.downcase)
                   '[Filtered]'
                 else
                   sentry_scrub(val, depth + 1)
                 end
    end
  end

  def sentry_scrub(value, depth = 0)
    return value if depth > 5
    return sentry_redact_string(value) if value.is_a?(String)
    return value.map { |item| sentry_scrub(item, depth + 1) } if value.is_a?(Array)
    return sentry_scrub_hash(value, depth) if value.is_a?(Hash)

    value
  end

  def sentry_filter_request(request)
    request.headers&.each_key do |header|
      request.headers[header] = '[Filtered]' if %w[Cookie cookie Authorization authorization X-Api-Key x-api-key].include?(header)
    end
    request.data = sentry_scrub(request.data) if request.data
  end

  def sentry_filter_breadcrumb(breadcrumb)
    breadcrumb.message = sentry_redact_string(breadcrumb.message) if breadcrumb.message
    breadcrumb.data = sentry_scrub(breadcrumb.data) if breadcrumb.data
  end

  def sentry_filter_event(event)
    event.message = sentry_redact_string(event.message) if event.message
    event.breadcrumbs&.each { |breadcrumb| sentry_filter_breadcrumb(breadcrumb) }
    event.extra = sentry_scrub(event.extra) if event.extra
    event.contexts = sentry_scrub(event.contexts) if event.contexts
  end

  def sentry_filter_exception(event)
    event.exception&.values&.each do |exc| # rubocop:disable Style/HashEachMethods
      exc.value = sentry_redact_string(exc.value) if exc.value
    end
  end

  def sentry_filter_user(user)
    user.delete(:email)
    user.delete(:username)
    user.delete(:ip_address)
  end

  def sentry_before_send(event, _hint)
    sentry_filter_request(event.request) if event.request
    sentry_filter_event(event)
    sentry_filter_exception(event)
    sentry_filter_user(event.user) if event.user
    event
  end

  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.enabled_environments = %w[staging production]
    config.traces_sample_rate = 0.1 if ENV['ENABLE_SENTRY_TRANSACTIONS']
    config.excluded_exceptions += ['Rack::Timeout::RequestTimeoutException', 'MutexApplicationJob::LockAcquisitionError']
    # LGPD: never send default PII (IP, headers, etc) — sentry_before_send
    # scrubs anything PII that slips into a breadcrumb or extra.
    config.send_default_pii = false
    config.before_send = method(:sentry_before_send)
  end
end
