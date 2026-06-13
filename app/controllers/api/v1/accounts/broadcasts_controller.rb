class Api::V1::Accounts::BroadcastsController < Api::V1::Accounts::BaseController
  before_action :fetch_broadcast, except: [:index, :create, :templates]
  before_action :authorize_action

  def index
    @broadcasts = policy_scope(Current.account.broadcasts).order(created_at: :desc)
  end

  def show; end

  def create
    @broadcast = Current.account.broadcasts.new(permitted_params)
    @broadcast.save!
    render :show
  end

  def update
    @broadcast.update!(permitted_params)
    render :show
  end

  def destroy
    @broadcast.destroy!
    head :ok
  end

  # Flip the broadcast live and kick off the adaptive dispatch loop.
  def launch
    @broadcast.status_running!
    Broadcasts::DispatchJob.perform_later(@broadcast.id)
    render :show
  end

  def pause
    @broadcast.status_paused!
    render :show
  end

  def audience_preview
    render json: { count: Broadcasts::AudienceResolver.new(@broadcast).contact_ids.length }
  end

  # Approved Meta templates for a Cloud API inbox, for the official-mode picker.
  def templates
    inbox = Current.account.inboxes.find(params[:inbox_id])
    channel = inbox.channel
    list = channel.respond_to?(:message_templates) ? Array(channel.message_templates) : []
    render json: { templates: list.select { |tpl| tpl['status']&.downcase == 'approved' } }
  end

  private

  def fetch_broadcast
    @broadcast = Current.account.broadcasts.find(params[:id])
  end

  def authorize_action
    case action_name
    when 'index', 'create', 'templates'
      authorize(Broadcast)
    else
      authorize(@broadcast)
    end
  end

  def permitted_params
    params.require(:broadcast).permit(
      :name, :inbox_id, :mode, :scheduled_at,
      message: {}, audience: {}, throttle: {}
    )
  end
end
