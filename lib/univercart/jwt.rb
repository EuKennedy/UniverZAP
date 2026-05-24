require 'openssl'
require 'base64'
require 'json'

module Univercart
  module Jwt
    Result = Struct.new(:ok, :claims, :reason, keyword_init: true)

    # Valida JWT HS256 emitido pelo Univercart.
    # Claims: sub (subscriptionId), email, name, role, iss='univercart',
    # aud=<partner_slug>, exp, iat, jti.
    def self.verify(jwt:, jwt_secret:, expected_audience:)
      parts = jwt.split('.')
      return Result.new(ok: false, reason: 'malformed') unless parts.length == 3

      header_seg, payload_seg, provided_sig = parts

      header = begin
        JSON.parse(b64url_decode(header_seg))
      rescue JSON::ParserError
        return Result.new(ok: false, reason: 'malformed')
      end
      return Result.new(ok: false, reason: 'malformed') unless header['alg'] == 'HS256' && header['typ'] == 'JWT'

      claims = begin
        JSON.parse(b64url_decode(payload_seg))
      rescue JSON::ParserError
        return Result.new(ok: false, reason: 'malformed')
      end

      expected_sig = hmac_b64url(jwt_secret, "#{header_seg}.#{payload_seg}")
      unless ActiveSupport::SecurityUtils.secure_compare(expected_sig, provided_sig)
        return Result.new(ok: false, reason: 'bad_signature')
      end

      now = Time.current.to_i
      return Result.new(ok: false, reason: 'expired') if claims['exp'].to_i < now
      return Result.new(ok: false, reason: 'bad_issuer') unless claims['iss'] == 'univercart'
      return Result.new(ok: false, reason: 'bad_audience') unless claims['aud'] == expected_audience

      Result.new(ok: true, claims: claims)
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
end
