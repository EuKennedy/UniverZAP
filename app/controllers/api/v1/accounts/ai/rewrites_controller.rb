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

    Current.account.conversations.find_by(display_id: params[:conversation_display_id])
  end

  def resolve_assistant(conversation)
    return Current.account.ai_assistants.active.find(params[:ai_assistant_id]) if params[:ai_assistant_id].present?

    conversation&.ai_assistant ||
      conversation&.inbox&.ai_assistant ||
      Current.account.ai_assistants.active.first
  end
end
