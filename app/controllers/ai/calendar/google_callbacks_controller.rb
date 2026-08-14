# Where Google sends the operator back after they authorise the calendar.
#
# Runs outside the dashboard session, so nothing here trusts a parameter: the
# agent this grant belongs to comes from the SIGNED state issued fifteen
# minutes earlier by Ai::CalendarConnectionsController.
class Ai::Calendar::GoogleCallbacksController < ApplicationController
  include GoogleCalendarConcern

  def show
    payload = verified_state
    return redirect_to(failure_path(nil, nil, 'invalid_state')) if payload.blank?

    connect(payload)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    redirect_to failure_path(payload&.dig(:account_id), payload&.dig(:assistant_id), 'google_error')
  end

  private

  def connect(payload)
    assistant = find_assistant(payload)
    return redirect_to(failure_path(payload[:account_id], payload[:assistant_id], 'agent_not_found')) if assistant.nil?

    token = exchange_code
    # No refresh token means an access token that dies in an hour with no way to
    # renew it. Refusing here is the whole point: the alternative is a
    # connection that looks healthy on screen and stops answering tomorrow.
    return redirect_to(failure_path(assistant.account_id, assistant.id, 'no_refresh_token')) if token.refresh_token.blank?

    Ai::Calendar::ConnectService.new(assistant: assistant, token: token).perform
    redirect_to success_path(assistant.account_id, assistant.id)
  rescue Ai::Calendar::ConnectService::AgendaTaken
    # Google grant already given at this point, and deliberately not kept: an
    # agent holding both agendas sends Anthropic duplicate tool names and stops
    # replying to everyone. The operator is sent back with the reason instead.
    redirect_to failure_path(assistant.account_id, assistant.id, 'agenda_taken')
  end

  def verified_state
    calendar_state_verifier.verify(params[:state]).symbolize_keys
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  # Scoped by the account that was in the signed state, so a crossed id cannot
  # attach somebody else's Google account to an agent.
  def find_assistant(payload)
    Ai::Assistant.find_by(id: payload[:assistant_id], account_id: payload[:account_id])
  end

  def exchange_code
    google_calendar_client.auth_code.get_token(params[:code], redirect_uri: calendar_redirect_uri)
  end

  def success_path(account_id, assistant_id)
    "/app/accounts/#{account_id}/athenas/#{assistant_id}?calendar=connected"
  end

  def failure_path(account_id, assistant_id, reason)
    return "/app/accounts/#{account_id}/athenas/#{assistant_id}?calendar=error&reason=#{reason}" if assistant_id.present?

    "/?calendar=error&reason=#{reason}"
  end
end
