# Connecting the operator's own Google account to ONE agent.
#
# Per agent and not per account: the same person may run a salon and a clinic
# as two agents, and their agendas have nothing to do with each other. The
# grant, the calendar and the appointments all hang off the assistant, so an
# agent can only ever see the calendar it was connected to.
class Api::V1::Accounts::Ai::CalendarConnectionsController < Api::V1::Accounts::OauthAuthorizationController
  include GoogleCalendarConcern

  before_action :set_assistant

  def show
    render json: { connection: @assistant.calendar_connections.active.first&.push_event_data }
  end

  # Returns the URL the browser should be sent to. The redirect is not issued
  # here because this is an XHR from the dashboard, and a 302 on an XHR lands
  # the operator nowhere.
  def create
    return render json: { success: false, error: 'google_oauth_not_configured' }, status: :unprocessable_entity if client_missing?

    url = google_calendar_client.auth_code.authorize_url(
      { redirect_uri: calendar_redirect_uri, scope: CALENDAR_SCOPE, response_type: 'code',
        state: calendar_state }.merge(OFFLINE_PARAMS)
    )
    render json: { success: true, url: url }
  end

  # Disconnecting is a local revoke. The events already written stay in the
  # owner's calendar: they are real appointments with real customers, and
  # removing an integration is not a reason to empty somebody's week.
  def destroy
    @assistant.calendar_connections.active.each { |connection| connection.revoke!('disconnected by operator') }
    head :ok
  end

  private

  def set_assistant
    @assistant = Current.account.ai_assistants.find(params[:assistant_id])
  end

  # Signed, short-lived, and carrying the agent id. Google hands `state` back
  # untouched on the callback, which runs outside the account session, so this
  # is the only thing proving which agent an authorisation was started for.
  def calendar_state
    calendar_state_verifier.generate(
      { account_id: Current.account.id, assistant_id: @assistant.id }, expires_in: 15.minutes
    )
  end

  def client_missing?
    GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil).blank? ||
      GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_SECRET', nil).blank?
  end
end
