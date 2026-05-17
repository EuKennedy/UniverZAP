class Api::V1::Accounts::Ai::SuggestionsController < Api::V1::Accounts::BaseController
  def create
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    result = Ai::SuggestReplyService.new(conversation: conversation).perform
    render json: { suggestion: result[:content], model: result[:model] }
  rescue Ai::ClaudeService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
