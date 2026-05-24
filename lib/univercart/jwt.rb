require 'openssl'
require 'base64'
require 'json'

module Univercart::Jwt
  Result = Struct.new(:ok, :claims, :reason, keyword_init: true)

  # Valida JWT HS256 emitido pelo Univercart. Claims esperadas:
  # sub, email, name, role, iss='univercart', aud=<partner_slug>, exp, iat, jti.
  def self.verify(jwt:, jwt_secret:, expected_audience:)
    parts = jwt.split('.')
    return fail_result('malformed') unless parts.length == 3

    header_seg, payload_seg, provided_sig = parts
    header = decode_segment(header_seg) or return fail_result('malformed')
    return fail_result('malformed') unless valid_header?(header)

    claims = decode_segment(payload_seg) or return fail_result('malformed')
    return fail_result('bad_signature') unless valid_signature?(jwt_secret, header_seg, payload_seg, provided_sig)

    validate_claims(claims, expected_audience)
  end

  def self.decode_segment(segment)
    JSON.parse(b64url_decode(segment))
  rescue JSON::ParserError
    nil
  end

  def self.valid_header?(header)
    header['alg'] == 'HS256' && header['typ'] == 'JWT'
  end

  def self.valid_signature?(jwt_secret, header_seg, payload_seg, provided_sig)
    expected_sig = hmac_b64url(jwt_secret, "#{header_seg}.#{payload_seg}")
    ActiveSupport::SecurityUtils.secure_compare(expected_sig, provided_sig)
  end

  def self.validate_claims(claims, expected_audience)
    now = Time.current.to_i
    return fail_result('expired') if claims['exp'].to_i < now
    return fail_result('bad_issuer') unless claims['iss'] == 'univercart'
    return fail_result('bad_audience') unless claims['aud'] == expected_audience

    Result.new(ok: true, claims: claims)
  end

  def self.fail_result(reason)
    Result.new(ok: false, reason: reason)
  end

  def self.b64url_decode(input)
    padded = input.tr('-_', '+/')
    pad = padded.length % 4
    padded += '=' * (4 - pad) unless pad.zero?
    Base64.decode64(padded)
  end

  def self.hmac_b64url(secret, data)
    digest = OpenSSL::HMAC.digest('SHA256', secret, data)
    Base64.urlsafe_encode64(digest, padding: false)
  end
end
