class Api::V1::Accounts::Ai::SummariesController < Api::V1::Accounts::BaseController
  def create
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    # Same authorization gate as the conversation show endpoint — without it
    # any agent in the account can summarise conversations they aren't
    # allowed to read.
    authorize(conversation, :show?)
    assistant = resolve_assistant(conversation)
    result = Ai::SummarizeService.new(conversation: conversation, assistant: assistant).perform
    render json: { summary: result[:content], model: result[:model] }
  rescue Ai::ClaudeService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def resolve_assistant(conversation)
    return Current.account.ai_assistants.active.find(params[:ai_assistant_id]) if params[:ai_assistant_id].present?

    conversation.ai_assistant || conversation.inbox.ai_assistant
  end
end
