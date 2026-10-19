# The salon's view of one contact, for the "Ficha da cliente" block in the
# conversation sidebar. Read-only: everything comes live from the belezaki
# agent API, scoped by the contact's phone (the key the two systems share), and
# is cached for a minute so reopening a conversation does not count twice
# against the salon's rate limit.
#
# Two calls because the agent API has no customer profile yet: the default
# window of `/appointments` is "yesterday onwards", so history needs its own
# `from`/`to`. Yesterday shows up in both and is deduped by id.
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

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { fetch(external_id) }
  rescue Ai::Belezaki::AgentClient::Error => e
    { status: 'unavailable', error: e.code }
  end

  private

  def fetch(external_id)
    client = Ai::Belezaki::AgentClient.new(external_id: external_id)
    current = client.appointments(phone: phone)
    return { status: 'unknown_client', salon: salon } if current['client'].blank?

    past = client.appointments(phone: phone, from: (Date.current - HISTORY_MONTHS.months).to_s, to: Date.yesterday.to_s)
    { status: 'ok', salon: salon, client: current['client'] }.merge(split(Array(current['appointments']) + Array(past['appointments'])))
  end

  def split(rows)
    future, history = rows.uniq { |row| row['id'] }.partition { |row| Time.iso8601(row['start']) >= Time.current }
    {
      next: future.find { |row| ACTIVE_STATUSES.include?(row['status']) },
      upcoming: future.sort_by { |row| row['start'] },
      history: history.sort_by { |row| row['start'] }.reverse.first(HISTORY_LIMIT)
    }
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
