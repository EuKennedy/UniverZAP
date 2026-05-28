class Public::Api::V1::CsatSurveyController < PublicController
  before_action :set_conversation
  before_action :set_message

  def show; end

  def update
    render json: { error: 'You cannot update the CSAT survey after 14 days' }, status: :unprocessable_entity and return if check_csat_locked

    @message.update!(message_update_params[:message])
  end

  private

  def set_conversation
    return if params[:id].blank?

    @conversation = Conversation.find_by!(uuid: params[:id])
  end

  # Lazy-create the input_csat message if the conversation doesn't have
  # one yet. By default Chatwoot only seeds it when the conversation is
  # resolved (via `Conversation#mute_or_resolve_csat_survey`), which
  # blocks operators from sharing the survey URL mid-conversation.
  # We seed-on-demand instead — same template, no resolve required.
  def set_message
    @message = @conversation.messages.find_by(content_type: 'input_csat')
    return if @message.present?

    MessageTemplates::Template::CsatSurvey.new(conversation: @conversation).perform
    @message = @conversation.messages.find_by!(content_type: 'input_csat')
  end

  def message_update_params
    params.permit(message: [{ submitted_values: [:name, :title, :value, { csat_survey_response: [:feedback_message, :rating] }] }])
  end

  def check_csat_locked
    (Time.zone.now.to_date - @message.created_at.to_date).to_i > 14
  end
end
