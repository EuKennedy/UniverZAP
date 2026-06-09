require 'openssl'
require 'base64'
require 'json'

# Verifier for the short-lived HS256 token the belezaki app mints to launch a
# buyer into Univerzap (SSO bridge). Mirrors Univercart::Jwt but is decoupled
# from Univercart: it trusts only the shared UNIVERZAP_BRIDGE_SECRET and the
# belezaki issuer. See docs reference UNIVERZAP_BRIDGE_INTEGRATION.md.
module Belezaki::BridgeJwt
  Result = Struct.new(:ok, :claims, :reason, keyword_init: true)

  EXPECTED_ISS = 'belezaki'.freeze
  EXPECTED_AUD = 'univerzap'.freeze

  def self.verify(jwt:, secret:)
    parts = jwt.to_s.split('.')
    return fail_result('malformed') unless parts.length == 3

    header_seg, payload_seg, provided_sig = parts
    header = decode_segment(header_seg) or return fail_result('malformed')
    return fail_result('malformed') unless valid_header?(header)

    claims = decode_segment(payload_seg) or return fail_result('malformed')
    return fail_result('bad_signature') unless valid_signature?(secret, header_seg, payload_seg, provided_sig)

    validate_claims(claims)
  end

  def self.valid_header?(header)
    header['alg'] == 'HS256' && header['typ'] == 'JWT'
  end

  def self.valid_signature?(secret, header_seg, payload_seg, provided_sig)
    expected = hmac_b64url(secret, "#{header_seg}.#{payload_seg}")
    ActiveSupport::SecurityUtils.secure_compare(expected, provided_sig)
  end

  def self.validate_claims(claims)
    now = Time.current.to_i
    return fail_result('expired')      if claims['exp'].to_i < now
    return fail_result('bad_issuer')   unless claims['iss'] == EXPECTED_ISS
    return fail_result('bad_audience') unless claims['aud'] == EXPECTED_AUD
    return fail_result('bad_role')     unless claims['role'] == 'ultra'
    return fail_result('no_email')     if claims['email'].to_s.strip.empty?
    return fail_result('no_jti')       if claims['jti'].to_s.strip.empty?

    Result.new(ok: true, claims: claims)
  end

  def self.decode_segment(segment)
    JSON.parse(b64url_decode(segment))
  rescue JSON::ParserError
    nil
  end

  def self.b64url_decode(input)
    padded = input.tr('-_', '+/')
    pad = padded.length % 4
    padded += '=' * (4 - pad) unless pad.zero?
    Base64.decode64(padded)
  end

  def self.hmac_b64url(secret, data)
    Base64.urlsafe_encode64(OpenSSL::HMAC.digest('SHA256', secret, data), padding: false)
  end

  def self.fail_result(reason)
    Result.new(ok: false, reason: reason)
  end
end
