# One `GET /salon` that proves a salon id: the shared key is right, the id
# exists and the salon's subscription is active. Failures come back as a short
# code the screen can explain, never as the salon's own message.
class Belezaki::SalonProbe
  class Failure < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  CODES = { 'http_401' => 'unauthorized', 'http_404' => 'not_found', 'entitlement_inactive' => 'inactive' }.freeze

  def initialize(external_id)
    @external_id = external_id
  end

  def perform
    raise Failure, 'not_configured' if Ai::Belezaki::AgentClient.api_key.blank?
    raise Failure, 'missing_external_id' if @external_id.blank?

    Ai::Belezaki::AgentClient.new(external_id: @external_id).salon || {}
  rescue Ai::Belezaki::AgentClient::Error => e
    raise Failure, CODES.fetch(e.code, 'unreachable')
  end
end
