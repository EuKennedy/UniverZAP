# OpenAI transcription, the fallback for a workspace with no ElevenLabs key.
#
# `gpt-4o-mini-transcribe` rather than `whisper-1`: whisper is no longer on
# OpenAI's pricing page, superseded by this line, and it is both cheaper and
# markedly better than whisper on the noisy phone audio this product deals with.
#
# The request is deliberately minimal (no response_format, no temperature): the
# defaults are json and 0, and every extra parameter is one more thing that can
# differ between models in a path that only runs when the primary is absent.
class Ai::Transcription::OpenAiAdapter < Ai::Transcription::BaseAdapter
  ENDPOINT = 'https://api.openai.com/v1/audio/transcriptions'.freeze
  MODEL = 'gpt-4o-mini-transcribe'.freeze

  def model
    MODEL
  end

  def call(file_part)
    response = connection.post(ENDPOINT) do |req|
      req.headers['Authorization'] = "Bearer #{@api_key}"
      req.body = { file: file_part, model: MODEL }
    end
    raise_for_status!(response, 'OpenAI')
    build_result(parse_json(response.body))
  end

  private

  # No duration in the plain json response, so the caller falls back to its own
  # estimate for billing. That estimate is pessimistic by design, which means
  # this path can over-charge slightly. Acceptable for a fallback; the primary
  # provider reports the real spoken length from its word timestamps.
  def build_result(body)
    Ai::Transcription::Result.new(text: body['text'].to_s.strip, model: MODEL, duration_seconds: nil)
  end
end
