# Everything the "Configurar negócio" tab reads and writes, in one place.
#
# One endpoint rather than five because the tab is a single form: the operator
# names the agenda, draws the week and saves. Splitting that into a request per
# field would let them leave the screen half-applied, with services that nobody
# can be booked for because the week was never saved.
class Api::V1::Accounts::Ai::CalendarSetupController < Api::V1::Accounts::BaseController
  before_action :ensure_admin
  before_action :fetch_assistant
  before_action :fetch_professional, only: [:update]

  def show
    render json: setup_payload
  end

  def update
    ActiveRecord::Base.transaction do
      update_professional
      update_setting
      replace_hours
    end
    render json: setup_payload
  rescue Ai::Calendar::ReplaceHoursService::Overlap => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end

  # Scoped to the current account's agents, so one workspace can never reach
  # another's agenda even with a guessed id.
  def fetch_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end

  # The agenda is created when the calendar is connected. Its absence means the
  # operator reached this screen without connecting, which the UI prevents and
  # a stale tab does not.
  def fetch_professional
    @professional = @assistant.calendar_professionals.first
    render json: { error: 'calendar_not_connected' }, status: :unprocessable_entity if @professional.nil?
  end

  def update_professional
    return if params[:professional].blank?

    @professional.update!(params.require(:professional).permit(:name, :timezone))
  end

  def update_setting
    return if params[:settings].blank?

    setting = @assistant.calendar_setting ||
              Ai::Calendar::Setting.new(ai_assistant_id: @assistant.id, account_id: Current.account.id)
    setting.update!(params.require(:settings).permit(:minimum_lead_minutes, :horizon_days, :cancellation_window_hours))
  end

  def replace_hours
    return if params[:hours].nil?

    ranges = params[:hours].map { |hour| hour.permit(:weekday, :starts_at, :ends_at).to_h.symbolize_keys }
    Ai::Calendar::ReplaceHoursService.new(professional: @professional, ranges: ranges).perform
  end

  def setup_payload
    professional = @professional || @assistant.calendar_professionals.first
    {
      connection: @assistant.calendar_connections.active.first&.push_event_data,
      professional: professional&.push_event_data,
      services: @assistant.calendar_services.order(:id).map(&:push_event_data),
      settings: (@assistant.calendar_setting || Ai::Calendar::Setting.new).push_event_data
    }
  end
end
