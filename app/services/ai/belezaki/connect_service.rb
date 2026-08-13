# Binds one agent to the belezaki salon its account already belongs to.
#
# There is no OAuth to run here: the agent API authenticates with a shared
# server-to-server key plus the salon id in a header, so "connecting" is the
# operator confirming WHICH salon this agent books on.
#
# The `GET /salon` call is the whole validation. One answer proves the shared key
# is right, the tenant exists and the salon is reachable — and it doubles as the
# probe for the base URL, so a wrong path fails on the operator's screen instead
# of in front of a customer on WhatsApp.
class Ai::Belezaki::ConnectService
  class NotLinked < StandardError; end
  class NotConfigured < StandardError; end
  class AgendaTaken < StandardError; end

  def initialize(assistant:)
    @assistant = assistant
  end

  def perform
    raise AgendaTaken, 'google calendar connected' if @assistant.calendar_connections.active.exists?
    raise NotConfigured, 'shared key missing' if Ai::Belezaki::AgentClient.api_key.blank?

    external_id = Ai::Belezaki::TenantResolver.external_id(@assistant.account)
    raise NotLinked, 'account has no belezaki salon' if external_id.blank?

    persist(external_id, probe(external_id))
  end

  private

  def probe(external_id)
    Ai::Belezaki::AgentClient.new(external_id: external_id).salon || {}
  end

  # Reconnecting updates the existing row rather than colliding with the
  # uniqueness rule. The operator's mental model is "connect", not "delete the
  # old one and then connect" — and a row left behind revoked would keep the
  # screen saying something the agent no longer does.
  def persist(external_id, salon)
    connection = @assistant.belezaki_connection || @assistant.build_belezaki_connection
    connection.update!(
      account_id: @assistant.account_id, external_id: external_id,
      salon_name: salon['name'], timezone: salon['timezone'].presence || 'America/Sao_Paulo',
      status: 'active', connected_at: Time.current, last_error: nil, last_error_at: nil
    )
    connection
  end
end
