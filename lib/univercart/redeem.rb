require 'net/http'
require 'uri'
require 'json'

module Univercart
  module Redeem
    # Marca o jti como usado no lado Univercart. Garante single-use:
    # 2ª chamada com mesmo jti retorna 410.
    def self.consume(jti:)
      uri = URI.join(ENV.fetch('UNIVERCART_API_BASE'), "/v1/tokens/#{jti}/redeem")
      req = Net::HTTP::Post.new(uri)
      req['Authorization']   = "Bearer #{ENV.fetch('UNIVERCART_API_KEY')}"
      req['Idempotency-Key'] = jti
      req['Content-Type']    = 'application/json'

      res = Net::HTTP.start(
        uri.hostname, uri.port,
        use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 8
      ) do |http|
        http.request(req)
      end

      res.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      Rails.logger.warn("[univercart.redeem] #{jti}: #{e.message}")
      false
    end
  end
end
