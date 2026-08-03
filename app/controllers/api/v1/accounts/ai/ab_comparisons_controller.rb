# The duels waiting for a verdict, and the verdict itself.
class Api::V1::Accounts::Ai::AbComparisonsController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant

  def index
    scope = @assistant.ab_comparisons.includes(:ai_invocation).order(created_at: :desc)
    scope = scope.where(ai_prompt_version_id: params[:version_id]) if params[:version_id].present?
    scope = scope.where(winner: nil) if params[:pending].present?
    render json: { items: scope.limit(50).map(&:push_event_data) }
  end

  # Records A / B / tie. The UI can hide which column is which until this lands
  # (blind mode): reviewers vote for the column they were told is new.
  def update
    comparison = @assistant.ab_comparisons.find(params[:id])
    comparison.update!(winner: params[:winner], reviewer_id: Current.user.id)
    render json: comparison.push_event_data
  end

  private

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  def fetch_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end
end
