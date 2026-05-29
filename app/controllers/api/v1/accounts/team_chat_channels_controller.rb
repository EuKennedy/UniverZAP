# Dashboard-side team-chat channel API. Session auth inherited from
# BaseController. Every fetch funnels through `Current.account` so
# cross-tenant ids 404 instead of leaking. The four default channels are
# seeded lazily on first index so existing accounts get them with no
# backfill migration.
class Api::V1::Accounts::TeamChatChannelsController < Api::V1::Accounts::BaseController
  before_action :fetch_channel, only: [:show, :update, :destroy]
  before_action :authorize_action

  def index
    seed_default_channels!
    channels = Current.account.team_chat_channels.active.ordered
    render json: channels.map(&:push_event_data)
  end

  def show
    render json: @channel.push_event_data
  end

  def create
    channel = Current.account.team_chat_channels.create!(
      channel_params.merge(kind: :custom, created_by_user: Current.user)
    )
    render json: channel.push_event_data, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: 'invalid_channel', message: e.record.errors.full_messages.to_sentence },
           status: :unprocessable_entity
  end

  def update
    @channel.update!(channel_params)
    render json: @channel.push_event_data
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: 'invalid_channel', message: e.record.errors.full_messages.to_sentence },
           status: :unprocessable_entity
  end

  # Soft-delete: default channels are protected (they anchor the workspace);
  # custom channels are archived, not destroyed, so history survives.
  def destroy
    if @channel.kind_default?
      return render json: { error: 'default_channel_protected',
                            message: I18n.t('errors.team_chat.default_channel_protected',
                                            default: 'Canais padrão não podem ser removidos.') },
                    status: :unprocessable_entity
    end

    @channel.update!(archived_at: Time.current)
    head :ok
  end

  private

  def fetch_channel
    @channel = Current.account.team_chat_channels.find(params[:id])
  end

  def authorize_action
    record = @channel || TeamChatChannel
    authorize(record)
  end

  def channel_params
    params.require(:team_chat_channel).permit(:name, :slug, :description)
  end

  def seed_default_channels!
    return if Current.account.team_chat_channels.exists?

    TeamChatChannel::DEFAULT_CHANNELS.each_with_index do |attrs, index|
      Current.account.team_chat_channels.create!(attrs.merge(kind: :default, position: index + 1))
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Concurrent first-loads can race on the unique slug index — the loser
    # just reads what the winner seeded. Swallow and continue.
  end
end
