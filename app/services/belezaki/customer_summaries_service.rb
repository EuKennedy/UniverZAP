# What the contacts list shows about each customer: the next appointment, the
# latest services, the usual professional and the money. Belezaki has no bulk
# route, so every contact not in the cache is one `clients/lookup`: callers send
# a small batch, the result stays cached for a while, and the first failure ends
# the batch instead of waiting on the same timeout once per contact.
class Belezaki::CustomerSummariesService
  MAX_BATCH = 5
  CACHE_TTL = 15.minutes
  LAST_SERVICES = 3
  CACHEABLE = %w[ok unknown_client].freeze

  def initialize(account:, contacts:)
    @account = account
    @contacts = contacts
  end

  def perform
    return @contacts.to_h { |contact| [contact.id, { status: 'not_linked' }] } if Belezaki::TenantResolver.external_id(@account).blank?

    cached = Rails.cache.read_multi(*@contacts.map { |contact| cache_key(contact) })
    @contacts.to_h { |contact| [contact.id, cached[cache_key(contact)] || lookup(contact)] }
  end

  private

  def lookup(contact)
    return { status: 'unavailable' } if @stopped

    card = Belezaki::CustomerCardService.new(account: @account, contact: contact).perform
    @stopped = card[:status] == 'unavailable'
    summary = summarize(card)
    Rails.cache.write(cache_key(contact), summary, expires_in: CACHE_TTL) if CACHEABLE.include?(card[:status])
    summary
  end

  def summarize(card)
    return { status: card[:status] } unless card[:status] == 'ok'

    done = card[:history].select { |row| row['status'] == 'done' }
    stats = card[:stats] || {}
    { status: 'ok', timezone: card.dig(:salon, :timezone), next: card[:next]&.slice('start', 'service', 'professional', 'status'),
      last_services: done.pluck('service').uniq.first(LAST_SERVICES), professional: usual_professional(done, card[:next]),
      total_spent_cents: stats['total_spent_cents'], visits: stats['visits'], no_shows: stats['no_shows'], last_visit_at: stats['last_visit_at'] }
  end

  def usual_professional(done, upcoming)
    done.pluck('professional').compact.tally.max_by(&:last)&.first || upcoming&.dig('professional')
  end

  def cache_key(contact)
    "belezaki/summary/#{@account.id}/#{contact.id}/#{contact.phone_number}"
  end
end
