# The four calls the scheduling module makes to Google, over plain HTTP.
#
# No client gem, for the same reason Ai::ClaudeService talks to Anthropic
# directly: it is four endpoints, we already have the pattern for a timed HTTP
# client with named failures, and the gem drags a dependency tree behind it.
#
# Access tokens are fetched on demand and never stored. They live an hour, so
# a stored one is a stored staleness, and the connection deliberately keeps
# only the refresh token.
class Ai::Calendar::GoogleClient
  class Error < StandardError; end
  # The operator removed our access from their Google account, or the refresh
  # token was invalidated. Distinct from a blip because the answer is different:
  # the agent has to STOP promising appointments, and somebody has to reconnect.
  class Revoked < Error; end

  TOKEN_URL = 'https://oauth2.googleapis.com/token'.freeze
  FREEBUSY_URL = 'https://www.googleapis.com/calendar/v3/freeBusy'.freeze
  EVENTS_URL = 'https://www.googleapis.com/calendar/v3/calendars/%<calendar_id>s/events'.freeze

  OPEN_TIMEOUT = 8
  READ_TIMEOUT = 20

  def initialize(connection)
    @connection = connection
  end

  # When the calendar is occupied, as GOOGLE sees it — which includes whatever
  # the owner put there by hand. That is the whole reason we read free/busy
  # instead of only subtracting our own appointments: the dentist blocks a slot
  # without anyone having to copy it into our tables.
  def busy(calendar_id:, from:, to:)
    body = post_json(FREEBUSY_URL, {
                       timeMin: from.utc.iso8601, timeMax: to.utc.iso8601,
                       items: [{ id: calendar_id }]
                     })
    periods = body.dig('calendars', calendar_id, 'busy') || []
    periods.map { |period| Time.zone.parse(period['start'])..Time.zone.parse(period['end']) }
  end

  def create_event(calendar_id:, payload:)
    post_json(format(EVENTS_URL, calendar_id: CGI.escape(calendar_id)), payload)
  end

  def update_event(calendar_id:, event_id:, payload:)
    request(:patch, "#{format(EVENTS_URL, calendar_id: CGI.escape(calendar_id))}/#{CGI.escape(event_id)}", payload)
  end

  # Google answers 410 when the event is already gone. That is the outcome the
  # caller wanted, so it is not an error.
  def delete_event(calendar_id:, event_id:)
    url = "#{format(EVENTS_URL, calendar_id: CGI.escape(calendar_id))}/#{CGI.escape(event_id)}"
    response = raw_request(:delete, url, nil)
    return true if response.code.to_i == 410

    handle!(response)
    true
  end

  private

  def post_json(url, payload)
    request(:post, url, payload)
  end

  def request(method, url, payload)
    handle!(raw_request(method, url, payload))
  end

  def raw_request(method, url, payload)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.request(build_request(method, uri, payload))
  end

  def build_request(method, uri, payload)
    klass = { post: Net::HTTP::Post, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.fetch(method)
    req = klass.new(uri.request_uri)
    req['Authorization'] = "Bearer #{access_token}"
    req['Content-Type'] = 'application/json'
    req.body = payload.to_json if payload
    req
  end

  def handle!(response)
    code = response.code.to_i
    return JSON.parse(response.body.presence || '{}') if code.between?(200, 299)
    # 401 is a token Google no longer honours. Recorded on the connection so the
    # screen can say why the agenda stopped, instead of the agent apologising
    # forever for something the operator could fix in one click.
    raise_revoked!("google answered #{code}") if code == 401

    raise Error, "google answered #{code}: #{response.body.to_s.truncate(200)}"
  end

  def access_token
    @access_token ||= fetch_access_token
  end

  def fetch_access_token
    response = token_response
    body = JSON.parse(response.body.presence || '{}')
    # `invalid_grant` is Google's way of saying the operator revoked us, or the
    # refresh token was rotated away. No retry helps.
    raise_revoked!(body['error_description'].presence || 'invalid_grant') if body['error'] == 'invalid_grant'
    raise Error, "token endpoint answered #{response.code}" unless response.code.to_i.between?(200, 299)

    body['access_token']
  end

  def token_response
    uri = URI.parse(TOKEN_URL)
    Net::HTTP.post_form(uri, {
                          client_id: GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil),
                          client_secret: GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_SECRET', nil),
                          refresh_token: @connection.encrypted_refresh_token,
                          grant_type: 'refresh_token'
                        })
  end

  def raise_revoked!(reason)
    @connection.revoke!(reason)
    raise Revoked, reason
  end
end
