class Api::V1::Accounts::Ai::RewritesController < Api::V1::Accounts::BaseController
  def create
    conversation = resolve_conversation
    assistant = resolve_assistant(conversation)
    result = Ai::RewriteService.new(
      content: params[:content],
      operation: params[:operation],
      assistant: assistant,
      conversation: conversation
    ).perform
    render json: { message: result[:content], model: result[:model] }
  rescue Ai::ClaudeService::Error => e
    Rails.logger.warn(
      "[Athenas] rewrite failed: #{e.message} operation=#{params[:operation]} " \
      "conv=#{params[:conversation_display_id]}"
    )
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def resolve_conversation
    return nil if params[:conversation_display_id].blank?

    conv = Current.account.conversations.find_by(display_id: params[:conversation_display_id])
    return nil if conv.blank?

    # Reading the conversation's transcript is implicit in any rewrite that
    # uses it as context — apply the same Pundit gate.
    authorize(conv, :show?)
    conv
  end

  def resolve_assistant(conversation)
    return Current.account.ai_assistants.active.find(params[:ai_assistant_id]) if params[:ai_assistant_id].present?

    # Deterministic fallback chain — last hop sorts by id so the picked
    # assistant is reproducible across requests instead of relying on
    # `.first` (insertion order from the DB).
    conversation&.ai_assistant ||
      conversation&.inbox&.ai_assistant ||
      Current.account.ai_assistants.active.order(:id).first
  end
end
