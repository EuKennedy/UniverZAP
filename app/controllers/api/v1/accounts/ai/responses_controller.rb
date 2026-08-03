# The supervision queue for one agent: what it said, what the guardrails
# thought, and what a human decided about it.
class Api::V1::Accounts::Ai::ResponsesController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant

  def index
    render json: Ai::ResponseQueueService.new(
      assistant: @assistant, filter: params[:filter], flag: params[:flag],
      page: params[:page] || 1, per_page: params[:per_page] || Ai::ResponseQueueService::PER_PAGE
    ).perform
  end

  private

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  # Scoped through Current.account: a response log carries customer text, so it
  # must never be reachable by raw assistant id.
  def fetch_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end
end
