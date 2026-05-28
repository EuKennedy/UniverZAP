# Root controller for the public Kanban API (v2). All endpoints under
# `/api/v2/kanban/*` inherit this base — authentication, error
# envelopes, scope enforcement, request audit and account scoping live
# here once instead of being copy-pasted across resources.
#
# Authentication: `Authorization: Bearer zk_live_xxx` header. The token
# is looked up by SHA-256 digest (stored once on creation). On a match
# we expose:
#   - `current_token`  — the KanbanApiToken row
#   - `current_account` — its account (drives all AR scoping)
#   - `Current.account` — set globally so model callbacks + services
#                          stay tenant-safe in the request thread.
#
# Authorization: each subclass declares `required_scope` either at the
# class level (applies to every action) or per-action via the helper
# `requires_scope :read_tasks`. Missing scope = 403.
class Api::V2::Kanban::BaseController < ActionController::API
  class AuthenticationError < StandardError; end
  class ScopeError < StandardError; end
  class NotFoundError < StandardError; end

  before_action :authenticate_kanban_token!
  before_action :enforce_scope!
  after_action  :track_token_usage

  rescue_from AuthenticationError, with: :render_unauthorized
  rescue_from ScopeError,          with: :render_forbidden
  rescue_from NotFoundError,       with: :render_not_found
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid,  with: :render_unprocessable

  class_attribute :required_scope, instance_writer: false

  attr_reader :current_token, :current_account

  # Subclasses can override this if the scope depends on the HTTP verb
  # (most do — index/show vs. create/update/destroy).
  def enforce_scope!
    scope = required_scope_for_action
    return if scope.nil?
    return if current_token.has_scope?(scope)

    raise ScopeError, "token missing required scope: #{scope}"
  end

  def required_scope_for_action
    return required_scope if required_scope.is_a?(String)

    # Subclasses may declare a hash: { read: 'read:tasks', write: 'write:tasks' }
    return nil unless required_scope.is_a?(Hash)

    case action_name.to_s
    when 'index', 'show'                    then required_scope[:read]
    when 'create', 'update', 'destroy', 'move', 'attach', 'detach' then required_scope[:write]
    end
  end

  private

  def authenticate_kanban_token!
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
end
