# Turns a customer's voice note into text the agent can answer.
#
# The contract it fills already existed and was never wired: `Message#content_for_llm`
# returns "[Voice Message] <text>" as soon as `attachment.meta['transcribed_text']`
# is present. Everything here exists to fill that one field, under OUR rules
# rather than the upstream Captain feature flags:
#
#   * multi-tenant by construction — the key, the cost and the audio all belong
#     to one account, and the job that calls this re-checks that;
#   * billed like every other AI call, through Ai::QuotaService before and
#     Ai::CreditLedger after, logged on ai_invocations with phase 'transcription'.
#     Anything that spends money without passing here is spend we absorb;
#   * transcribed in FULL. Feeding the agent a partial version of what the
#     customer said is the same class of bug as truncating the price table
#     before the model sees it, and it is not worth the fraction of a cent that
#     partial transcription would save.
class Ai::TranscriptionService
  class Error < StandardError; end

  # Both vendors reject uploads past 25 MB *decimal*. Using 25.megabytes (binary)
  # leaks the 25.0–26.2 MB range upstream as a 413.
  MAX_BYTES = 25_000_000
  # Anything longer than this is a recording, not a message to an agent. It is
  # kept as an attachment; it just is not transcribed.
  MAX_DURATION_SECONDS = 600
  # Pre-flight ceiling only. Opus voice notes sit near 2 KB/s, so 1 KB/s
  # deliberately over-estimates the length: the quota gate should refuse a
  # borderline case, not discover the shortfall after paying for it.
  PESSIMISTIC_BYTES_PER_SECOND = 1_000

  def initialize(attachment:, assistant: nil)
    @attachment = attachment
    @message = attachment.message
    @account = @message&.account
    @assistant = assistant
  end

  # Returns the text, or nil when there was nothing to do. Raises only on a
  # provider failure the caller may want to retry.
  def perform
    return existing_transcription if existing_transcription.present?
    return nil unless transcribable?

    adapter = build_adapter
    return nil if adapter.nil?

    Ai::QuotaService.check_transcription!(
      account: @account, model: adapter.model, duration_seconds: estimated_seconds
    )
    transcribe_with(adapter)
  end

  private

  def existing_transcription
    @existing_transcription ||= @attachment.meta&.dig('transcribed_text').presence
  end

  def transcribable?
    owned_audio? && within_provider_limits?
  end

  # The audio, the credential and the bill all belong to one account. A crossed
  # id must never make one workspace's voice note run on another workspace's key.
  def owned_audio?
    return false if @account.blank? || @assistant.blank?
    return false if @assistant.account_id != @account.id

    @attachment.file_type.to_s == 'audio'
  end

  # Past either limit the file stays attached; it just is not transcribed.
  def within_provider_limits?
    blob = @attachment.file&.blob
    return false if blob.blank?

    blob.byte_size <= MAX_BYTES && estimated_seconds <= MAX_DURATION_SECONDS
  end

  def estimated_seconds
    (@attachment.file.blob.byte_size / PESSIMISTIC_BYTES_PER_SECOND.to_f).ceil
  end

  # ElevenLabs first when the workspace has a key, because Scribe is markedly
  # better on noisy Brazilian Portuguese phone audio. Falls back to whatever key
  # exists so a workspace without one still gets voice notes understood instead
  # of the agent answering "[Attachment]".
  def build_adapter
    if elevenlabs_key.present?
      Ai::Transcription::ElevenLabsAdapter.new(api_key: elevenlabs_key)
    elsif openai_key.present?
      Ai::Transcription::OpenAiAdapter.new(api_key: openai_key)
    else
      Rails.logger.info("[Athenas audio] no transcription key for account=#{@account.id}; skipping")
      nil
    end
  end

  # Per-agent key first, platform key as fallback — the same shape the Anthropic
  # key already uses, so a workspace can bring its own vendor account.
  def elevenlabs_key
    @elevenlabs_key ||= @assistant&.resolved_elevenlabs_key.presence ||
                        ENV.fetch('ELEVENLABS_API_KEY', nil)
  end

  def openai_key
    @openai_key ||= @assistant&.resolved_openai_key.presence || ENV.fetch('OPENAI_API_KEY', nil)
  end

  def transcribe_with(adapter)
    started_at = Time.zone.now
    result = with_downloaded_file { |part| adapter.call(part) }
    return nil if result.text.blank?

    persist!(result)
    record_invocation(result, started_at)
    result.text
  end

  # Streamed to a temp file rather than read into memory: a 25 MB upload held in
  # a Sidekiq thread's heap is the kind of thing that only hurts under load.
  def with_downloaded_file
    blob = @attachment.file.blob
    Tempfile.create(['athenas-audio', extension_for(blob)], binmode: true) do |tmp|
      blob.download { |chunk| tmp.write(chunk) }
      tmp.rewind
      yield Faraday::Multipart::FilePart.new(tmp, blob.content_type, File.basename(tmp.path))
    end
  end

  # Both providers key their decoder off the filename extension, and a WhatsApp
  # voice note frequently arrives with none.
  def extension_for(blob)
    from_name = File.extname(blob.filename.to_s)
    return from_name if from_name.present?

    subtype = blob.content_type.to_s.split(';').first.to_s.split('/').last
    subtype.present? ? ".#{subtype.sub('x-', '')}" : '.ogg'
  end

  def persist!(result)
    # Merge, never replace: `meta` is shared with whatever else the channel
    # stored on this attachment.
    @attachment.update!(meta: (@attachment.meta || {}).merge('transcribed_text' => result.text))
    @message.reload
  end

  # Same log every other AI call writes, so the cost of voice shows up next to
  # the cost of thinking instead of hiding outside the ledger.
  def record_invocation(result, started_at)
    seconds = result.duration_seconds || estimated_seconds
    cents = Ai::PricingCalculator.transcription_cost_cents_brl(model: result.model, duration_seconds: seconds)
    invocation = create_invocation(result, started_at, seconds, cents)
    debit(invocation, result, seconds, cents)
  rescue StandardError => e
    # A billing or logging hiccup must never cost the customer their answer:
    # the transcription is already persisted at this point.
    Rails.logger.error("[Athenas audio] could not record transcription cost: #{e.message}")
  end

  def create_invocation(result, started_at, seconds, cents)
    Ai::Invocation.create!(
      ai_assistant: @assistant, account: @account,
      conversation_id: @message.conversation_id, message_id: @message.id,
      phase: 'transcription', model: result.model, status: 'success',
      duration_ms: ((Time.zone.now - started_at) * 1000).to_i,
      cost_brl: cents / 100.0, sandbox: @message.conversation&.sandbox? || false,
      user_message: "[audio #{seconds.round}s]"
    )
  end

  def debit(invocation, result, seconds, cents)
    return if cents.zero?

    Ai::CreditLedger.new(@account).debit!(
      invocation: invocation, cents_brl: cents,
      description: "#{result.model} #{seconds.round}s de áudio"
    )
  end
end
