# The Google grant used for SCHEDULING, deliberately separate from
# GoogleConcern.
#
# That one exists for the e-mail inbox and asks for https://mail.google.com/.
# Widening it to cover the calendar would force every operator who already
# connected an inbox to authorise again, and would hand mailbox access to an
# agent that only needs to read free/busy and write an event.
module GoogleCalendarConcern
  extend ActiveSupport::Concern

  # `calendar.events` writes the appointment. `calendar.readonly` is what lets
  # us ask free/busy, which is the whole reason the owner's own entries — the
  # dentist, the lunch — block a slot without anyone having to copy them here.
  # `email` is only so the screen can say WHICH account is connected.
  CALENDAR_SCOPE = [
    'email',
    'https://www.googleapis.com/auth/calendar.events',
    'https://www.googleapis.com/auth/calendar.readonly'
  ].join(' ').freeze

  # Google returns a refresh token only on the FIRST authorisation, and only
  # when both of these are set. Without them a second connection attempt comes
  # back with an access token that dies in an hour and no way to renew it, and
  # nothing fails until the agent is asked for a slot the next morning.
  OFFLINE_PARAMS = { access_type: 'offline', prompt: 'consent' }.freeze

  # Its OWN credentials, which is the whole point of the paragraph above and was
  # not what the code did: it reused GOOGLE_OAUTH_CLIENT_ID, the key Chatwoot
  # uses for SSO. Setting that key to make scheduling work also switched on the
  # "sign in with Google" button on the login screen of every installation, and
  # anyone who set it in the environment instead of Super Admin got a module
  # insisting it was unconfigured while the button sat there.
  CLIENT_ID_KEY = 'GOOGLE_CALENDAR_CLIENT_ID'.freeze
  CLIENT_SECRET_KEY = 'GOOGLE_CALENDAR_CLIENT_SECRET'.freeze

  def google_calendar_client
    ::OAuth2::Client.new(
      GlobalConfigService.load(CLIENT_ID_KEY, nil),
      GlobalConfigService.load(CLIENT_SECRET_KEY, nil),
      site: 'https://oauth2.googleapis.com',
      authorize_url: 'https://accounts.google.com/o/oauth2/auth',
      token_url: 'https://accounts.google.com/o/oauth2/token'
    )
  end

  # One fixed URI, because Google matches it exactly against what is registered
  # in the Cloud console. Which agent the grant belongs to travels in the signed
  # `state` instead.
  def calendar_redirect_uri
    "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/ai/calendar/google/callback"
  end

  def calendar_state_verifier
    Rails.application.message_verifier(:athenas_calendar_oauth)
  end
end
