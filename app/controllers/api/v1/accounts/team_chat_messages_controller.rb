# Messages within a single team-chat channel. Nested under
# `/team_chat_channels/:channel_id/messages`. Real-time delivery is via
# AccountTeamChatChannel — this REST surface backs the initial load,
# pagination, edit and delete.
class Api::V1::Accounts::TeamChatMessagesController < Api::V1::Accounts::BaseController
  PAGE_SIZE = 40

  before_action :fetch_channel
  before_action :fetch_message, only: [:update, :destroy]
  before_action :authorize_action

  # Returns up to PAGE_SIZE messages oldest→newest. `before_id` walks back
  # through history for infinite scroll: pass the id of the topmost loaded
  # message to fetch the page before it.
  def index
    scope = @channel.messages.chronological
    scope = scope.where('team_chat_messages.id < ?', params[:before_id]) if params[:before_id].present?
    messages = scope.reorder(created_at: :desc, id: :desc).limit(PAGE_SIZE).includes(:user)
    render json: messages.reverse.map(&:push_event_data)
  end

  def create
    message = @channel.messages.create!(user: Current.user, content: message_params[:content])
    render json: message.push_event_data, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: 'invalid_message', message: e.record.errors.full_messages.to_sentence },
           status: :unprocessable_entity
  end

  def update
    @message.update!(content: message_params[:content], edited_at: Time.current)
    render json: @message.push_event_data
  end

  def destroy
    @message.destroy!
    head :ok
  end

  private

  def fetch_channel
    # Nested under `resources :team_chat_channels` → Rails names the parent
    # param after the resource (`team_chat_channel_id`), NOT `channel_id`.
    # Reading the wrong key made `find(nil)` raise RecordNotFound → every
    # message POST/GET 404'd ("nenhuma mensagem chega").
    @channel = Current.account.team_chat_channels.find(params[:team_chat_channel_id])
  end

  def fetch_message
    @message = @channel.messages.find(params[:id])
  end

  def authorize_action
    record = @message || @channel
    authorize(record, policy_action)
  end

  # index/create authorize against the channel (membership gate);
  # update/destroy authorize against the message (author/admin gate).
  def policy_action
    case action_name
    when 'index'   then :messages?
    when 'create'  then :post_message?
    else "#{action_name}?".to_sym
    end
  end

  def message_params
    params.require(:team_chat_message).permit(:content)
  end
end
