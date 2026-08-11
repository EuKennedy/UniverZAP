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

  # Not a provider ceiling (ElevenLabs accepts far larger files). It is a sanity
  # bound: past this it is not a voice note, and holding a 25 MB upload in a
  # Sidekiq thread is the kind of thing that only hurts under load.
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

    blocker = untranscribable_reason
    return give_up!(blocker) if blocker

    adapter = build_adapter
    return give_up!('nenhuma chave do ElevenLabs configurada (ELEVENLABS_API_KEY)') if adapter.nil?

    Ai::QuotaService.check_transcription!(
      account: @account, model: adapter.model, duration_seconds: estimated_seconds
    )
    transcribe_with(adapter)
  rescue StandardError => e
    # Recorded, then re-raised untouched: the caller decides what a provider
    # failure means for the turn, and this only makes sure the reason survives.
    give_up!(e.message.to_s.truncate(300))
    raise
  end

  # Why the customer's voice note did not become text, written where somebody
  # will actually see it.
  #
  # Every one of these paths used to return nil in silence, so the only visible
  # symptom was the agent telling a customer it could not hear — an explanation
  # the model invents, and a plausible one, which is what made it cost hours to
  # track down. An invalid API key was being reported by ElevenLabs on every
  # single call and reached nobody.
  def give_up!(reason)
    Rails.logger.info(
      "[Athenas audio] not transcribed attachment=#{@attachment.id} " \
      "account=#{@account&.id}: #{reason}"
    )
    stamp_meta('transcription_error' => reason)
    nil
  end

  private

  def existing_transcription
    @existing_transcription ||= @attachment.meta&.dig('transcribed_text').presence
  end

  # Nil when the voice note can be transcribed; otherwise the reason it cannot,
  # in words an operator can act on. One method rather than three booleans
  # because the reason IS the product here: "false" is what made this whole
  # path invisible.
  #
  # The first three checks are the tenant guard: the audio, the credential and
  # the bill all belong to one account, and a crossed id must never make one
  # workspace's voice note run on another workspace's key. Order preserved.
  def untranscribable_reason
    return 'anexo sem conta ou agente associado' if @account.blank? || @assistant.blank?
    return 'anexo pertence a outra conta' if @assistant.account_id != @account.id
    return "anexo nao e audio (tipo: #{@attachment.file_type})" unless @attachment.file_type.to_s == 'audio'

    blob_blocker
  end

  # Past either limit the file stays attached; it just is not transcribed.
  def blob_blocker
    blob = @attachment.file&.blob
    return 'arquivo nao esta no storage (so a URL externa do canal)' if blob.blank?
    return "arquivo maior que o limite de #{MAX_BYTES / 1_000_000} MB" if blob.byte_size > MAX_BYTES
    return "audio mais longo que o limite de #{MAX_DURATION_SECONDS / 60} min" if estimated_seconds > MAX_DURATION_SECONDS

    nil
  end

  def estimated_seconds
    (@attachment.file.blob.byte_size / PESSIMISTIC_BYTES_PER_SECOND.to_f).ceil
  end

  # ElevenLabs Scribe, and nothing else.
  #
  # A silent fallback to a second-best model was the tempting design and the
  # wrong one: the agent would keep answering, the transcription would quietly
  # get worse, and nobody would know which model produced the reply that lost a
  # sale. With one provider, a missing key means voice notes are not understood,
  # which is visible on the first one instead of invisible forever.
  def build_adapter
    return Ai::Transcription::ElevenLabsAdapter.new(api_key: elevenlabs_key) if elevenlabs_key.present?

    Rails.logger.info("[Athenas audio] no ElevenLabs key for account=#{@account.id}; skipping")
    nil
  end

  # Per-agent key first, platform key as fallback. Same shape the Anthropic key
  # already uses, so a workspace can bring its own ElevenLabs account and its
  # own bill.
  def elevenlabs_key
    @elevenlabs_key ||= @assistant&.resolved_elevenlabs_key.presence ||
                        ENV.fetch('ELEVENLABS_API_KEY', nil)
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
    # Clearing the error alongside is what makes a retry after a fixed key look
    # fixed, instead of leaving a stale reason next to a working transcript.
    stamp_meta('transcribed_text' => result.text, 'transcription_error' => nil)
    @message.reload
  end

  # Merge, never replace: `meta` is shared with whatever else the channel stored
  # on this attachment. Nil values are dropped rather than written.
  def stamp_meta(values)
    merged = (@attachment.meta || {}).merge(values).compact
    @attachment.update!(meta: merged)
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
