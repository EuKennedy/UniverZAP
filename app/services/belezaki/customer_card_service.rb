# The salon's view of one contact, for the "Agenda no belezaki" section of the
# customer sheet in the conversation sidebar. Read-only: everything comes live
# from the belezaki agent API, scoped by the contact's phone (the key the two
# systems share), and is cached for a minute so reopening a conversation does
# not count twice against the salon's rate limit.
#
# One call to `clients/lookup` carries profile, money, attendance and the
# agenda. A salon still on the version before that route answers 404 for it,
# and then the agenda alone (two `appointments` calls) is better than a blank
# card until the salon updates.
class Belezaki::CustomerCardService
  CACHE_TTL = 60.seconds
  HISTORY_MONTHS = 12
  HISTORY_LIMIT = 10
  ACTIVE_STATUSES = %w[confirmed scheduled].freeze

  def initialize(account:, contact:)
    @account = account
    @contact = contact
  end

  def perform
    external_id = Belezaki::TenantResolver.external_id(@account)
    return { status: 'not_linked' } if external_id.blank?
    return { status: 'no_phone' } if phone.blank?

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { fetch(Ai::Belezaki::AgentClient.new(external_id: external_id)) }
  rescue Ai::Belezaki::AgentClient::Error => e
    { status: 'unavailable', error: e.code }
  end

  private

  def fetch(client)
    profile = client.client_lookup(phone: phone)
    return { status: 'unknown_client', salon: salon } if profile['client'].blank?

    upcoming = Array(profile['upcoming'])
    { status: 'ok', salon: salon, client: profile['client'], stats: profile['stats'],
      next: next_of(upcoming), upcoming: upcoming, history: Array(profile['history']) }
  rescue Ai::Belezaki::AgentClient::Error => e
    raise unless e.code == 'http_404'

    fetch_from_agenda(client)
  end

  # The default window of `/appointments` is "yesterday onwards", so history
  # needs its own range; yesterday shows up in both and is deduped by id.
  def fetch_from_agenda(client)
    current = client.appointments(phone: phone)
    return { status: 'unknown_client', salon: salon } if current['client'].blank?

    past = client.appointments(phone: phone, from: (Date.current - HISTORY_MONTHS.months).to_s, to: Date.yesterday.to_s)
    { status: 'ok', salon: salon, client: current['client'], stats: nil }
      .merge(split(Array(current['appointments']) + Array(past['appointments'])))
  end

  def split(rows)
    future, history = rows.uniq { |row| row['id'] }.partition { |row| Time.iso8601(row['start']) >= Time.current }
    upcoming = future.sort_by { |row| row['start'] }
    { next: next_of(upcoming), upcoming: upcoming, history: history.sort_by { |row| row['start'] }.reverse.first(HISTORY_LIMIT) }
  end

  def next_of(upcoming)
    upcoming.find { |row| ACTIVE_STATUSES.include?(row['status']) }
  end

  # Name and timezone were written on the hook by the connect probe; an account
  # linked only through the login bridge has no hook and no salon block.
  def salon
    settings = Belezaki::TenantResolver.hook(@account)&.settings
    return nil if settings.blank?

    { name: settings['salon_name'], timezone: settings['timezone'] }
  end

  def phone
    @contact.phone_number
  end

  def cache_key
    "belezaki/customer/#{@account.id}/#{@contact.id}/#{phone}"
  end
end
