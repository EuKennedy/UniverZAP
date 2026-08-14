# Turns a fresh Google grant into everything the scheduling module needs to
# exist: the connection, the one agenda the MVP shows, and the rules.
#
# Idempotent by (assistant, google_email). Connecting the same account twice is
# something operators do when they are unsure whether it worked, and the second
# attempt must refresh the token rather than leave two grants where the agent
# has to guess which one is live.
class Ai::Calendar::ConnectService
  # Raised rather than silently taking over: the belezaki agenda declares five of
  # the same tool names, and an agent holding both sends Anthropic a duplicate
  # name — which fails the whole request with a 400 and stops the agent replying
  # to anyone. The belezaki side has refused this since it shipped; this is the
  # missing half, for an operator who connects the agendas in the other order.
  class AgendaTaken < StandardError; end

  # Google's alias for the calendar the account already uses. Writing there is
  # deliberate: whatever the owner puts in it by hand — the dentist, the lunch —
  # then blocks a slot without anybody having to copy it into our tables.
  PRIMARY_CALENDAR_ID = 'primary'.freeze
  USERINFO_URL = 'https://www.googleapis.com/oauth2/v3/userinfo'.freeze

  def initialize(assistant:, token:)
    @assistant = assistant
    @token = token
  end

  def perform
    raise AgendaTaken, 'belezaki agenda connected' if @assistant.belezaki_connection&.active?

    profile = fetch_profile
    connection = upsert_connection(profile)
    ensure_professional(connection, profile)
    ensure_setting
    connection
  end

  private

  def upsert_connection(profile)
    connection = @assistant.calendar_connections.find_or_initialize_by(google_email: profile[:email])
    connection.assign_attributes(
      account_id: @assistant.account_id,
      encrypted_refresh_token: @token.refresh_token,
      status: 'active', last_error: nil, last_error_at: nil
    )
    connection.save!
    connection
  end

  # One professional is created on connect and the MVP never says the word: the
  # screen calls it the salon's agenda. It exists from day one so that a second
  # chair is an INSERT rather than a migration. The name is a starting point —
  # the operator renames it in "Configurar negócio", and that name is what the
  # customer hears and what goes on the event.
  def ensure_professional(connection, profile)
    return if connection.professionals.exists?(calendar_id: PRIMARY_CALENDAR_ID)

    connection.professionals.create!(
      ai_assistant_id: @assistant.id, account_id: @assistant.account_id,
      name: profile[:name].presence || profile[:email].to_s.split('@').first,
      calendar_id: PRIMARY_CALENDAR_ID
    )
  end

  # Asks the TABLE, not the association. The assistant is the same object across
  # a reconnect and its cached has_one still answers nil after the first call
  # wrote the row, which is how the second connect attempt used to die on the
  # unique index — a 500 for the operator who only wanted to make sure it had
  # worked. The rescue covers the other way in: two connects racing.
  def ensure_setting
    return if Ai::Calendar::Setting.exists?(ai_assistant_id: @assistant.id)

    Ai::Calendar::Setting.create!(ai_assistant_id: @assistant.id, account_id: @assistant.account_id)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # The email is what the screen shows so the operator can tell WHICH account is
  # connected. A failure here must not lose the grant: the token is the valuable
  # part, and a nameless connection is still a working one.
  def fetch_profile
    body = @token.get(USERINFO_URL).parsed
    { email: body['email'], name: body['name'] }
  rescue StandardError => e
    Rails.logger.warn("[Athenas calendar] could not read the Google profile: #{e.message}")
    { email: "google-#{@assistant.id}", name: nil }
  end
end
