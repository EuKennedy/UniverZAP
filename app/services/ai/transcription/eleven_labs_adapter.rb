# ElevenLabs Scribe.
#
# Chosen over Whisper for this product specifically: WhatsApp voice notes in
# Brazilian Portuguese, recorded on a phone, with background noise and regional
# accent. That is where whisper-1 degrades most, and its documented failure mode
# on near-silence is to hallucinate repeated phrases.
#
# The language is deliberately NOT pinned. Scribe auto-detects, and a workspace
# that serves more than one language would otherwise get every other language
# force-decoded as Portuguese, which is worse than a slightly weaker detection.
class Ai::Transcription::ElevenLabsAdapter < Ai::Transcription::BaseAdapter
  ENDPOINT = 'https://api.elevenlabs.io/v1/speech-to-text'.freeze
  MODEL = 'scribe_v1'.freeze

  def model
    MODEL
  end

  def call(file_part)
    response = connection.post(ENDPOINT) do |req|
      req.headers['xi-api-key'] = @api_key
      req.body = { file: file_part, model_id: MODEL }
    end
    raise_for_status!(response, 'ElevenLabs')
    build_result(parse_json(response.body))
  end

  private

  def build_result(body)
    Ai::Transcription::Result.new(
      text: body['text'].to_s.strip,
      model: MODEL,
      duration_seconds: duration_from(body)
    )
  end

  # Scribe returns word-level timestamps, so the end of the last word is the
  # real spoken length. Better than the file duration, which includes trailing
  # silence the operator should not pay for.
  def duration_from(body)
    last = Array(body['words']).last
    last && last['end'] ? last['end'].to_f : nil
  end
end
