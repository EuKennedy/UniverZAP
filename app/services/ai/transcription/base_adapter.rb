# Shared plumbing for speech-to-text providers.
#
# The provider is behind an interface on purpose. Transcription vendors move
# fast, the contract this feeds (`attachment.meta['transcribed_text']`) has been
# stable in this codebase for a long time, and the day we want to switch should
# cost one class, not a migration.
#
# Subclasses implement #call(file_part) and #model.
class Ai::Transcription::BaseAdapter
  class Error < StandardError; end
  # Upstream blip: the caller may retry the whole turn later.
  class TransientError < Error; end

  # A voice note is short. A minute of wall clock is already far past the point
  # where the customer has given up waiting for the agent to answer.
  TIMEOUT_SECONDS = 60
  OPEN_TIMEOUT_SECONDS = 15

  def initialize(api_key:)
    @api_key = api_key
  end

  def call(_file_part)
    raise NotImplementedError
  end

  def model
    raise NotImplementedError
  end

  private

  def connection
    @connection ||= Faraday.new do |f|
      f.request :multipart
      f.options.timeout = TIMEOUT_SECONDS
      f.options.open_timeout = OPEN_TIMEOUT_SECONDS
    end
  end

  # 5xx and 429 are blips worth retrying later; 4xx means the request or the
  # key is wrong and retrying forever would only burn the queue.
  def raise_for_status!(response, provider)
    return if response.success?

    message = "#{provider} #{response.status}: #{response.body.to_s.truncate(200)}"
    raise(response.status >= 500 || response.status == 429 ? TransientError : Error, message)
  end

  def parse_json(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    {}
  end
end
