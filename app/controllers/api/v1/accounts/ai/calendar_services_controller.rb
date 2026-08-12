# What the business sells time for: "progressiva, 90min, R$ 219".
#
# Its own resource and not part of the setup form, because services are a list
# the operator adds to over months while the week and the agenda name are set
# once. Duration and buffer live here rather than in a knowledge document
# precisely so the slot arithmetic stays ours: left as prose, the model would
# be adding 90 minutes to 14:00 by itself.
class Api::V1::Accounts::Ai::CalendarServicesController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant
  before_action :fetch_service, only: [:update, :destroy]

  def index
    render json: { payload: @assistant.calendar_services.order(:id).map(&:push_event_data) }
  end

  def create
    service = @assistant.calendar_services.create!(permitted_params.merge(account_id: Current.account.id))
    render json: service.push_event_data
  end

  def update
    @service.update!(permitted_params)
    render json: @service.push_event_data
  end

  # Deactivated, never deleted: an appointment already booked points at this
  # service, and the owner still has to be able to read what Thursday was for.
  def destroy
    @service.update!(active: false)
    head :ok
  end

  private

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  # Scoped to the current account's agents, so one workspace can never reach
  # another's services even with a guessed id.
  def fetch_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end

  def fetch_service
    @service = @assistant.calendar_services.find(params[:id])
  end

  def permitted_params
    params.require(:service).permit(:name, :duration_minutes, :buffer_minutes, :price_cents, :global, :active)
  end
end
