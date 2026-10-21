# Talks to a shop's WooCommerce REST API (wp-json/wc/v3) with the keys the
# admin pasted. The store URL comes from a person, so every call goes out only
# over https and never to private address space — same rule as the Athenas
# HTTP tools, re-checked at call time because DNS can change.
class Woocommerce::Client
  class Error < StandardError; end

  OPEN_TIMEOUT = 8
  READ_TIMEOUT = 20
  PAGE_SIZE = 50
  WEBHOOK_TOPICS = %w[order.created order.updated].freeze

  def initialize(store_url:, consumer_key:, consumer_secret:)
    @base = store_url.to_s.chomp('/')
    @key = consumer_key
    @secret = consumer_secret
  end

  # Cheapest call that proves the URL, the keys and the read permission.
  def probe!
    get('orders', per_page: 1)
    true
  end

  def orders(page: 1, modified_after: nil)
    params = { page: page, per_page: PAGE_SIZE, orderby: 'modified', order: 'asc' }
    params[:modified_after] = modified_after.utc.iso8601 if modified_after
    get('orders', params)
  end

  def create_webhook(topic:, delivery_url:, secret:)
    post('webhooks', name: "UniverZAP #{topic}", topic: topic, delivery_url: delivery_url, secret: secret, status: 'active')
  end

  def delete_webhook(id)
    request(Net::HTTP::Delete, "webhooks/#{id}", { force: true })
  end

  private

  def get(path, params = {})
    request(Net::HTTP::Get, path, params)
  end

  def post(path, body)
    request(Net::HTTP::Post, path, {}, body)
  end

  def request(verb, path, params = {}, body = nil)
    uri = safe_uri!("#{@base}/wp-json/wc/v3/#{path}")
    # Keys as query parameters, not basic auth: many WordPress hosts drop the
    # Authorization header, and WooCommerce accepts both over https.
    uri.query = URI.encode_www_form(params.merge(consumer_key: @key, consumer_secret: @secret))
    req = verb.new(uri)
    req['Accept'] = 'application/json'
    if body
      req['Content-Type'] = 'application/json'
      req.body = body.to_json
    end
    parse(http_for(uri).request(req))
  rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError, Resolv::ResolvError => e
    raise Error, "loja indisponível: #{e.message}"
  end

  def http_for(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.max_retries = 0
    http
  end

  def parse(response)
    data = response.body.present? ? JSON.parse(response.body) : {}
    return data if response.is_a?(Net::HTTPSuccess)

    message = data.is_a?(Hash) ? data['message'] : nil
    raise Error, "WooCommerce respondeu #{response.code}#{": #{message}" if message}"
  rescue JSON::ParserError
    raise Error, "WooCommerce respondeu #{response.code} sem JSON (a URL é de uma loja WooCommerce?)"
  end

  def safe_uri!(url)
    uri = URI.parse(url)
    raise Error, 'a URL da loja precisa começar com https://' unless uri.scheme == 'https'

    ip = IPAddr.new(Resolv.getaddress(uri.host))
    raise Error, 'endereço da loja não permitido' if Ai::CustomToolExecutor::PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }

    uri
  rescue URI::InvalidURIError
    raise Error, 'URL da loja inválida'
  end
end
