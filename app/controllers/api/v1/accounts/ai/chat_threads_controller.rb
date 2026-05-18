class Api::V1::Accounts::Ai::ChatThreadsController < Api::V1::Accounts::BaseController
  before_action :set_thread, only: %i[show update destroy]

  def index
    threads = Current.account.ai_chat_threads.for_user(Current.user).active.recent
    threads = threads.for_conversation(params[:conversation_id]) if params[:conversation_id].present?
    @threads = threads.limit(50)
    render json: @threads.map(&:push_event_data)
  end

  def show
    render json: @thread.push_event_data.merge(messages: @thread.chat_messages.map(&:push_event_data))
  end

  def create
    thread = build_thread
    return render_thread(thread) if thread_params[:initial_message].blank?

    result = Ai::ChatService.new(thread: thread, user_message: thread_params[:initial_message]).perform
    render json: thread_payload(thread, result)
  rescue Ai::ClaudeService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @thread.update!(thread_update_params)
    render json: @thread.push_event_data
  end

  def destroy
    @thread.archive!
    head :no_content
  end

  private

  def set_thread
    @thread = Current.account.ai_chat_threads.for_user(Current.user).find(params[:id])
  end

  def build_thread
    assistant = Current.account.ai_assistants.active.find(thread_params[:ai_assistant_id])
    Current.account.ai_chat_threads.create!(
      user: Current.user,
      ai_assistant: assistant,
      conversation_id: thread_params[:conversation_id],
      title: thread_params[:title].presence || default_title(thread_params[:initial_message])
    )
  end

  def thread_params
    params.permit(:ai_assistant_id, :conversation_id, :title, :initial_message)
  end

  def thread_update_params
    params.permit(:title)
  end

  def default_title(initial_message)
    initial_message.to_s.truncate(80).presence || I18n.t('athenas.chat.default_thread_title', default: 'Nova conversa')
  end

  def render_thread(thread)
    render json: thread.push_event_data.merge(messages: [])
  end

  def thread_payload(thread, result)
    thread.push_event_data.merge(
      messages: [result[:user_message], result[:assistant_message]].compact.map(&:push_event_data)
    )
  end
end
