require 'openssl'

module Univercart::Signature
  REPLAY_WINDOW_SECONDS = 300 # 5 min

  # Verifica X-Univercart-Signature no formato: t=<ts>,v1=<hex>.
  # HMAC SHA-256 sobre "<ts>.<raw_body>". SEMPRE use raw body — NUNCA o JSON parseado.
  def self.verify(raw_body:, header:, secret:)
    parsed = parse_header(header)
    return false unless parsed

    return false if replay?(parsed[:timestamp])

    expected = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{parsed[:timestamp]}.#{raw_body}")
    ActiveSupport::SecurityUtils.secure_compare(expected, parsed[:signature])
  end

  def self.parse_header(header)
    return nil if header.blank?

    parts = header.split(',').each_with_object({}) do |kv, h|
      k, v = kv.split('=', 2)
      h[k] = v
    end

    timestamp = parts['t']&.to_i
    signature = parts['v1']
    return nil if timestamp.nil? || timestamp.zero? || signature.blank?

    { timestamp: timestamp, signature: signature }
  end

  def self.replay?(timestamp)
    (Time.current.to_i - timestamp).abs > REPLAY_WINDOW_SECONDS
  end
end
