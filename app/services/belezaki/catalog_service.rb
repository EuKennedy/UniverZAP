# The salon's catalogue — services and professionals — as the agent API
# answers it, cached for ten minutes per account: it changes a few times a
# month and is read every time a conversation sidebar opens.
class Belezaki::CatalogService
  CACHE_TTL = 10.minutes

  def initialize(account:, refresh: false)
    @account = account
    @refresh = refresh
  end

  def perform
    external_id = Belezaki::TenantResolver.external_id(@account)
    return { status: 'not_linked' } if external_id.blank?

    Rails.cache.delete(cache_key) if @refresh
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { fetch(Ai::Belezaki::AgentClient.new(external_id: external_id)) }
  rescue Ai::Belezaki::AgentClient::Error => e
    { status: 'unavailable', error: e.code }
  end

  private

  def fetch(client)
    { status: 'ok', salon: Belezaki::TenantResolver.salon(@account),
      services: Array(client.services['services']),
      professionals: Array(client.professionals['professionals']),
      fetched_at: Time.current.iso8601 }
  end

  def cache_key
    "belezaki/catalog/#{@account.id}"
  end
end
