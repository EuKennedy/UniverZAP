# Dashboard-side management of `KanbanApiToken` rows. The raw token is
# returned ONCE on create and stored as a SHA-256 digest server-side.
# Subsequent show/list responses only expose the `token_prefix` so the
# operator can identify which key is which without exposing the secret.
class Api::V1::Accounts::KanbanApiTokensController < Api::V1::Accounts::BaseController
  before_action :fetch_token, only: [:show, :destroy, :revoke]
  before_action :check_authorization

  def index
    render json: Current.account.kanban_api_tokens.order(created_at: :desc).map(&:push_event_data)
  end

  def show
    render json: @token.push_event_data
  end

  def create
    token = KanbanApiToken.generate!(
      account: Current.account,
      created_by_user: Current.user,
      name: params.require(:name),
      scopes: Array(params[:scopes]).map(&:to_s),
      expires_at: params[:expires_at].presence
    )
    # `raw_token` is exposed here ONLY — never again. The operator MUST
    # copy it now or rotate.
    render json: token.push_event_data.merge(raw_token: token.raw_token), status: :created
  end

  def destroy
    @token.destroy!
    head :ok
  end

  def revoke
    @token.revoke!(by_user: Current.user)
    render json: @token.push_event_data
  end

  private

  def fetch_token
    @token = Current.account.kanban_api_tokens.find(params[:id])
  end
end
