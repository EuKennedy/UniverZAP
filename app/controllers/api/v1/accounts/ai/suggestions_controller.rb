class Api::V1::Accounts::Ai::SuggestionsController < Api::V1::Accounts::BaseController
  def create
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    # Account scoping above stops cross-tenant access, but a restricted agent
    # can still see conversations on inboxes they shouldn't read. Gate the AI
    # suggestion behind the same policy as opening the conversation.
    authorize(conversation, :show?)
    assistant = resolve_assistant(conversation)
    result = Ai::SuggestReplyService.new(conversation: conversation, assistant: assistant).perform
    render json: { suggestion: result[:content], model: result[:model] }
  rescue Ai::ClaudeService::Error => e
    Rails.logger.warn("[Athenas] suggest_reply failed: #{e.message} conv=#{params[:conversation_id]}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def resolve_assistant(conversation)
    return Current.account.ai_assistants.active.find(params[:ai_assistant_id]) if params[:ai_assistant_id].present?

    conversation.ai_assistant || conversation.inbox.ai_assistant
  end
end
