# Root controller for the public Tasks API (v2). Mirrors the
# Api::V2::Kanban::BaseController architecture so a single bearer-token
# scheme covers both domains. Authentication, scope enforcement,
# error envelopes and pagination helpers all live here once.
#
# Subclasses declare:
#   self.required_scope = { read: 'read:user_tasks', write: 'write:user_tasks' }
#
# Authentication: `Authorization: Bearer zk_live_xxx`. Token lookup is
# constant-time via SHA-256 digest; matched token's account drives
# `Current.account` for the duration of the request.
class Api::V2::Tasks::BaseController < ActionController::API
  class AuthenticationError < StandardError; end
  class ScopeError < StandardError; end

  before_action :authenticate_token!
  before_action :enforce_scope!
  after_action  :track_token_usage

  rescue_from AuthenticationError, with: :render_unauthorized
  rescue_from ScopeError,          with: :render_forbidden
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid,  with: :render_unprocessable

  class_attribute :required_scope, instance_writer: false

  attr_reader :current_token, :current_account

  def enforce_scope!
    scope = required_scope_for_action
    return if scope.nil?
    return if current_token.includes_scope?(scope)

    raise ScopeError, "token missing required scope: #{scope}"
  end

  def required_scope_for_action
    return required_scope if required_scope.is_a?(String)
    return nil unless required_scope.is_a?(Hash)

    case action_name.to_s
    when 'index', 'show'                               then required_scope[:read]
    when 'create', 'update', 'destroy', 'assign', 'complete' then required_scope[:write]
    end
  end

  private

  def authenticate_token!
    raw = bearer_token
    raise AuthenticationError, 'missing bearer token' if raw.blank?

    token = KanbanApiToken.authenticate(raw)
    raise AuthenticationError, 'invalid or revoked token' if token.nil?

    @current_token = token
    @current_account = token.account
    Current.account = @current_account
  end

  def bearer_token
    header = request.headers['Authorization'].to_s
    return nil unless header.start_with?('Bearer ')

    header.split(' ', 2).last
  end

  def track_token_usage
    @current_token&.track_use!(remote_ip: request.remote_ip)
  end

  def render_unauthorized(error)
    render json: { error: 'unauthorized', message: error.message }, status: :unauthorized
  end

  def render_forbidden(error)
    render json: { error: 'forbidden', message: error.message }, status: :forbidden
  end

  def render_not_found(_error)
    render json: { error: 'not_found', message: 'resource not found' }, status: :not_found
  end

  def render_unprocessable(error)
    render json: { error: 'unprocessable_entity', errors: error.record.errors.as_json }, status: :unprocessable_entity
  end

  # `{ data, meta }` envelope — same shape as the kanban v2 API.
  def paginate(scope)
    page = (params[:page] || 1).to_i.clamp(1, 100_000)
    per = (params[:per_page] || 25).to_i.clamp(1, 100)
    @_total_count = scope.count
    @_total_pages = (@_total_count.to_f / per).ceil
    @_page = page
    @_per = per
    scope.offset((page - 1) * per).limit(per)
  end

  def meta_for(_scope)
    {
      page: @_page,
      per_page: @_per,
      total: @_total_count,
      total_pages: @_total_pages
    }
  end
end
