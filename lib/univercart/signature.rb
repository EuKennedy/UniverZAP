require 'openssl'

module Univercart
  module Signature
    REPLAY_WINDOW_SECONDS = 300 # 5 min

    # Verifica X-Univercart-Signature no formato: t=<ts>,v1=<hex>.
    # HMAC SHA-256 sobre "<ts>.<raw_body>". SEMPRE use raw body — NUNCA o JSON parseado.
    def self.verify(raw_body:, header:, secret:)
      return false if header.blank?

      parts = header.split(',').each_with_object({}) do |kv, h|
        k, v = kv.split('=', 2)
        h[k] = v
      end

      timestamp    = parts['t']&.to_i
      provided_sig = parts['v1']
      return false if timestamp.nil? || timestamp.zero? || provided_sig.blank?

      now = Time.current.to_i
      return false if (now - timestamp).abs > REPLAY_WINDOW_SECONDS

      expected = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{raw_body}")

      ActiveSupport::SecurityUtils.secure_compare(expected, provided_sig)
    end
  end
end
