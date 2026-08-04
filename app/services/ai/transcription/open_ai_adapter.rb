# OpenAI Whisper.
#
# Kept as the fallback so a workspace with no ElevenLabs key still gets voice
# notes understood instead of the agent answering "[Attachment]".
class Ai::Transcription::OpenAiAdapter < Ai::Transcription::BaseAdapter
  ENDPOINT = 'https://api.openai.com/v1/audio/transcriptions'.freeze
  MODEL = 'whisper-1'.freeze

  def model
    MODEL
  end

  def call(file_part)
    response = connection.post(ENDPOINT) do |req|
      req.headers['Authorization'] = "Bearer #{@api_key}"
      # temperature 0.0 suppresses Whisper's documented habit of spiralling into
      # repeated phrases on silence. verbose_json is what carries `duration`,
      # which is what the operator is billed on.
      req.body = { file: file_part, model: MODEL, temperature: '0.0', response_format: 'verbose_json' }
    end
    raise_for_status!(response, 'OpenAI')
    build_result(parse_json(response.body))
  end

  private

  def build_result(body)
    Ai::Transcription::Result.new(
      text: body['text'].to_s.strip,
      model: MODEL,
      duration_seconds: body['duration']&.to_f
    )
  end
end
