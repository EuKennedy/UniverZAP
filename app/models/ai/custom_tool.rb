# A tenant-configured HTTP tool the AI agent can call mid-conversation — the
# generic "Integrações" mechanism. Each record belongs to ONE agent in ONE
# workspace and carries that workspace's own endpoint + credentials, so a tool
# one workspace connects is invisible and unusable to every other account.
# Nothing here is global or hardcoded: univercart is simply the first record a
# workspace creates through the Integrações tab.
#
# Mirrors the proven Captain::CustomTool contract (endpoint, method, auth,
# param_schema, Liquid templates) but lives in the OSS tree and plugs into the
# Athenas tool loop (Ai::Agent::ToolLoopService), not the `agents` gem — so it
# survives the FOSS build, which strips enterprise/.
class Ai::CustomTool < ApplicationRecord
  self.table_name = 'ai_custom_tools'

  HTTP_METHODS = %w[GET POST].freeze
  AUTH_TYPES = %w[none bearer basic api_key].freeze
  MAX_SLUG_LENGTH = 64
  # A hostname pointing at loopback/private space is the classic SSRF target.
  # This blocks the obvious ones at save time; the executor re-checks the
  # RESOLVED ip at call time (a hostname can resolve to 127.0.0.1).
  DISALLOWED_HOSTS = ['localhost', /\.local\z/i].freeze
  # The leading identifier of a Liquid variable, so we can tell which params the
  # URL already consumes. Tolerates `{{id}}`, `{{ id }}`, `{{- id }}` and
  # `{{ id | url_encode }}`.
  TEMPLATE_VARIABLE = /\{\{-?\s*([a-zA-Z_]\w*)/

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account

  before_validation :generate_slug, on: :create

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :ai_assistant_id }, length: { maximum: MAX_SLUG_LENGTH }
  validates :endpoint_url, presence: true
  validates :http_method, inclusion: { in: HTTP_METHODS }
  validates :auth_type, inclusion: { in: AUTH_TYPES }
  validate :endpoint_must_be_safe
  validate :param_schema_must_be_array

  scope :enabled, -> { where(enabled: true) }

  # The Anthropic tool schema fed to the model in the tool loop.
  def to_tool_definition
    {
      name: slug,
      description: description.to_s,
      input_schema: { type: 'object', properties: schema_properties, required: schema_required }
    }
  end

  # Serialization for the API/UI. auth_config is DELIBERATELY omitted: the
  # credentials go in write-only and must never be handed back to the browser.
  def push_event_data
    {
      id: id, title: title, slug: slug, description: description, endpoint_url: endpoint_url,
      http_method: http_method, auth_type: auth_type, param_schema: param_schema, enabled: enabled
    }
  end

  def build_request_url(params)
    rendered = render_endpoint(params)
    return rendered unless http_method == 'GET'

    append_query(rendered, leftover_params(params))
  end

  def build_request_body(params)
    return nil if request_template.blank?

    render_template(request_template, params)
  end

  def build_auth_headers
    case auth_type
    when 'bearer' then { 'Authorization' => "Bearer #{auth_config['token']}" }
    when 'api_key' then api_key_header
    else {}
    end
  end

  def build_basic_auth_credentials
    return nil unless auth_type == 'basic'

    [auth_config['username'], auth_config['password']]
  end

  def format_response(raw_body)
    return raw_body if response_template.blank?

    render_template(response_template, { 'response' => parse_json(raw_body) })
  end

  private

  # Values are URL-encoded BEFORE Liquid substitutes them. Rendered raw, a
  # product name with a space produced an invalid URI, URI.parse raised inside
  # the executor, and the agent reported the useless "não consegui completar
  # essa ação agora" instead of a search result.
  def render_endpoint(params)
    return endpoint_url if endpoint_url.exclude?('{{')

    render_template(endpoint_url, params.to_h.transform_values { |value| ERB::Util.url_encode(stringify(value)) })
  end

  # Params the URL template did not consume travel as the query string.
  #
  # Without this, a GET tool configured the obvious way — endpoint
  # https://api.example.com/products plus a `search` param, no {{ }} anywhere —
  # went out as a bare GET with the search term dropped on the floor. The agent
  # then "found nothing" no matter what the catalogue held, and fell back to
  # guessing product ids. POST has had the equivalent fallback since the raw
  # input started being posted as the JSON body; GET never did.
  #
  # GET only, deliberately: on a POST the leftovers are already the body, and
  # repeating them in the query would send each one twice.
  def append_query(url, params)
    return url if params.blank?

    uri = URI.parse(url)
    pairs = URI.decode_www_form(uri.query.to_s) + params.map { |key, value| [key.to_s, stringify(value)] }
    uri.query = URI.encode_www_form(pairs)
    uri.to_s
  end

  def leftover_params(params)
    consumed = endpoint_url.to_s.scan(TEMPLATE_VARIABLE).flatten
    params.to_h.reject { |key, _value| consumed.include?(key.to_s) }
  end

  def stringify(value)
    return value if value.is_a?(String)
    return value.to_json if value.is_a?(Array) || value.is_a?(Hash)

    value.to_s
  end

  def api_key_header
    return {} unless auth_config['location'] == 'header'

    { auth_config['name'] => auth_config['key'] }
  end

  def schema_properties
    Array(param_schema).each_with_object({}) do |param, acc|
      acc[param['name']] = { 'type' => param['type'], 'description' => param['description'] }
    end
  end

  def schema_required
    Array(param_schema).select { |param| param.fetch('required', true) }.pluck('name')
  end

  def generate_slug
    return if slug.present? || title.blank?

    self.slug = title.parameterize(separator: '_').truncate(MAX_SLUG_LENGTH, omission: '')
  end

  def render_template(template, context)
    Liquid::Template.parse(template, error_mode: :strict)
                    .render(context.deep_stringify_keys, strict_variables: true, strict_filters: true)
  rescue Liquid::Error => e
    raise "Template rendering failed: #{e.message}"
  end

  def parse_json(body)
    JSON.parse(body)
  rescue JSON::ParserError
    body
  end

  def param_schema_must_be_array
    return if param_schema.is_a?(Array)

    errors.add(:param_schema, 'must be an array of parameter definitions')
  end

  def endpoint_must_be_safe
    return if endpoint_url.blank?

    uri = safe_parse_uri(endpoint_url)
    return errors.add(:endpoint_url, 'must be a valid URL') if uri.nil?

    errors.add(:endpoint_url, 'must use HTTPS') unless uri.scheme == 'https'
    validate_host(uri)
  end

  def safe_parse_uri(url)
    # Strip Liquid syntax so a templated URL still validates.
    URI.parse(url.gsub(/\{\{[^}]+\}\}/, 'x'))
  rescue URI::InvalidURIError
    nil
  end

  def validate_host(uri)
    host = uri.host
    return errors.add(:endpoint_url, 'must have a hostname') if host.blank?
    return errors.add(:endpoint_url, 'cannot be an IP address') if ip_literal?(host)
    return unless DISALLOWED_HOSTS.any? { |pattern| pattern.is_a?(Regexp) ? host.match?(pattern) : host.casecmp?(pattern) }

    errors.add(:endpoint_url, 'points to a disallowed host')
  end

  def ip_literal?(host)
    /\A\d{1,3}(\.\d{1,3}){3}\z/.match?(host) || host.include?(':')
  end
end
