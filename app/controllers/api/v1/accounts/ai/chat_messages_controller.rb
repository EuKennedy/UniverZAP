class Api::V1::Accounts::Ai::ChatMessagesController < Api::V1::Accounts::BaseController
  before_action :set_thread

  def index
    @messages = @thread.chat_messages
    render json: @messages.map(&:push_event_data)
  end

  def create
    result = Ai::ChatService.new(thread: @thread, user_message: params[:content]).perform
    render json: {
      user_message: result[:user_message].push_event_data,
      assistant_message: result[:assistant_message].push_event_data
    }
  rescue Ai::ClaudeService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_thread
    @thread = Current.account.ai_chat_threads.for_user(Current.user).find(params[:chat_thread_id])
  end
end
