# 👍 👎 ⭐ on one agent reply, and the conversion of a correction into something
# the agent uses.
#
# Rating and applying are separate actions on purpose, but a correction that CAN
# be applied is applied on the way in: the whole point of the loop is that the
# next customer does not receive the same wrong answer, and an operator should
# not have to remember a second click for that to be true.
class Api::V1::Accounts::Ai::ResponseFeedbacksController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant
  before_action :fetch_invocation

  def create
    feedback = upsert_feedback
    apply!(feedback) if feedback.immediate? && !feedback.applied?
    render json: payload(feedback)
  end

  # Re-run the conversion for a correction that was recorded but never applied,
  # typically because the first attempt failed.
  def apply
    feedback = @invocation.response_feedbacks.pending_application.order(created_at: :desc).first
    return render json: { error: 'no pending correction' }, status: :unprocessable_entity if feedback.blank?

    apply!(feedback)
    render json: payload(feedback)
  end

  private

  def upsert_feedback
    feedback = Ai::ResponseFeedback.find_or_initialize_by(
      ai_invocation_id: @invocation.id, reviewer_id: Current.user.id
    )
    feedback.assign_attributes(
      account: Current.account, ai_assistant: @assistant,
      rating: permitted_params[:rating], reason: permitted_params[:reason],
      corrected_text: permitted_params[:corrected_text]
    )
    feedback.save!
    feedback
  end

  # A failed conversion must not lose the verdict: the feedback row is already
  # saved, so the operator sees "recorded, not applied" and can retry.
  def apply!(feedback)
    Ai::FeedbackApplicationService.new(feedback: feedback).perform
  rescue Ai::FeedbackApplicationService::NotApplicable => e
    Rails.logger.info("[Athenas feedback] not applied feedback=#{feedback.id}: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[Athenas feedback] apply failed feedback=#{feedback.id}: #{e.message}")
  end

  def payload(feedback)
    feedback.reload.push_event_data.merge(
      applied: feedback.applied?,
      # What the correction became, so the UI can link straight to it.
      training_title: feedback.ai_training&.title,
      intent_name: feedback.ai_intent&.name
    )
  end

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  def fetch_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end

  # Through the assistant, never by raw id: a log row carries customer text.
  def fetch_invocation
    @invocation = @assistant.invocations.find(params[:response_id])
  end

  def permitted_params
    params.require(:feedback).permit(:rating, :reason, :corrected_text)
  end
end
