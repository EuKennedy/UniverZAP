# rubocop:disable Metrics/ClassLength
class Ai::AutopilotReplyJob < ApplicationJob
  # Dedicated lane (see config/sidekiq.yml): below :high so a message a human
  # agent typed always goes out first, above :medium so a customer-facing AI
  # reply never waits behind bulk imports/exports. The lane gives per-feature
  # queue depth/latency and room to split into its own process later; it does
  # not isolate the thread pool while one sidekiq drains every queue.
  queue_as :ai_replies

  RATE_LIMIT_WINDOW = 1.minute
  MAX_ATTEMPTS = 5

  # The customer who thinks out loud: "oi" / "vc tem a progressiva?" / "aquela
  # de 1L" arrives as three messages in five seconds, but it is ONE question.
  #
  # Every incoming message still enqueues a turn; they just start late enough
  # for the rest of the burst to land, and then all but the last stand down (see
  # #outrun?). The winner sees the whole burst in its context window and answers
  # it as the single thought it was.
  #
  # The delay is not a cost. An answer that lands 300ms after the customer hit
  # send reads as a machine; a few seconds of apparent reading and typing is
  # what the behaviour toggles on this agent are for in the first place.
  DEBOUNCE_WINDOW = 8.seconds

  # An Anthropic blip used to be swallowed here and the customer simply never
  # got an answer. Now the turn is retried with a growing delay, and when the
  # attempts run out it dies LOUDLY (dead-letter log) instead of silently.
  # Safe to retry: the reply is deduped by trigger message id under the
  # conversation row lock, and a superseded turn is dropped (see #superseded?).
  retry_on Ai::ClaudeService::TransientError, wait: :polynomially_longer, attempts: MAX_ATTEMPTS do |job, error|
    message_id, assistant_id = job.arguments
    Rails.logger.error(
      "[Athenas autopilot] dead-letter after #{MAX_ATTEMPTS} attempts " \
      "message=#{message_id} assistant=#{assistant_id}: #{error.message}"
    )
    message = Message.find_by(id: message_id)
    # No retry is coming, so the turn's log rows must stop being `pending`.
    # Every earlier attempt left rows open on purpose; this is where they close.
    close_out_turn!(message&.conversation, assistant_id, message_id, handoff: false)
    # Handling the error here keeps the job out of Sidekiq's Dead set, so
    # without this the customer's dropped turn would be invisible to on-call.
    # Report it explicitly instead of re-raising (re-raising would hand the job
    # back to Sidekiq's own retry cycle on top of the attempts above).
    ChatwootExceptionTracker.new(error, account: message&.account).capture_exception
  end

  # Closes out log rows for a turn that generated text nobody received.
  # `handoff` separates the two reasons that happens: the guardrails
  # deliberately handed the customer to a human, or the send itself fell over.
  # Class-level because the dead-letter block above runs without an instance in
  # scope, and that is precisely the path that must not leave rows open.
  def self.close_out_turn!(conversation, assistant_id, message_id, handoff:)
    return if conversation.blank? || message_id.blank?

    # rubocop:disable Rails/SkipsModelValidations
    turn_invocations(conversation, assistant_id, message_id)
      .awaiting_delivery.update_all(delivery_status: 'failed', handoff: handoff)
    # rubocop:enable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn("[Athenas autopilot] could not close out invocation: #{e.message}")
  end

  # Exactly the calls this turn made. `trigger_message_id` is stamped by
  # Ai::AutopilotReplyService, so no time window and no cross-turn bleed.
  def self.turn_invocations(conversation, assistant_id, message_id)
    Ai::Invocation.where(conversation_id: conversation.id, ai_assistant_id: assistant_id,
                         phase: 'autopilot', trigger_message_id: message_id)
  end

  def perform(message_id, assistant_id)
    message = Message.find_by(id: message_id)
    assistant = Ai::Assistant.find_by(id: assistant_id)
    return unless message && assistant

    conversation = message.conversation
    return unless same_account?(assistant, conversation)

    with_tenant_context(conversation) { deliver_reply(conversation, assistant, message) }
  rescue Ai::ClaudeService::TransientError
    # Must precede the generic clause: re-raised so `retry_on` above gets it
    # instead of the failure being swallowed. The log rows stay `pending` on
    # purpose — the turn is going to be retried.
    raise
  rescue StandardError => e
    handle_turn_failure(e, message, assistant_id)
  end

  private

  # Every terminal failure of a turn has to close out its log rows. They differ
  # only in whether the customer was deliberately handed to a human and whether
  # on-call gets paged.
  def handle_turn_failure(error, message, assistant_id)
    case error
    when Ai::AutopilotReplyService::LoopSuppressed
      # Intentional silence: the reply would have repeated a recent turn.
      # Logged at info — this is the loop-breaker working as designed.
      Rails.logger.info("[Athenas autopilot] #{error.message}")
      hand_off!(message, assistant_id)
    when Ai::Agent::ToolLoopService::PromiseUnfulfilled
      # The reply was going to promise a lookup the agent has no later turn to
      # make. Pages rather than logs: the customer asked something the tools
      # were supposed to answer and nobody answered it.
      Rails.logger.error("[Athenas autopilot] #{error.message}")
      hand_off!(message, assistant_id)
    when Ai::AutopilotReplyService::UngroundedClaim
      # The bot kept quoting a value that exists nowhere in the operator's data.
      # Staying silent beats inventing a price, but it IS a lost reply, so this
      # pages instead of just logging.
      Rails.logger.error("[Athenas autopilot] #{error.message}")
      hand_off!(message, assistant_id)
      ChatwootExceptionTracker.new(error, account: message&.account).capture_exception
    when Ai::ClaudeService::Error
      Rails.logger.error("[Athenas autopilot] failed for message=#{message&.id}: #{error.message}")
      mark_delivery_failed!(message&.conversation, assistant_id, message&.id, handoff: false)
    else
      raise error
    end
  end

  def hand_off!(message, assistant_id)
    mark_delivery_failed!(message&.conversation, assistant_id, message&.id, handoff: true)
  end

  # Give the agent turn a clean, correctly-scoped Current so the outgoing
  # message event is never attributed to a stale actor/tenant left on this
  # Sidekiq thread by an earlier job (Current is a bare thread-local with no
  # per-job auto-reset). Scoped fix for the agent path; the app-wide migration
  # to ActiveSupport::CurrentAttributes is tracked separately.
  def with_tenant_context(conversation)
    Current.reset
    Current.account = conversation.account
    yield
  ensure
    Current.reset
  end

  # Defense-in-depth tenant guard: never let an assistant from another account
  # answer this conversation, even if a cross-account ai_assistant_id somehow
  # slipped past the model validation (raw SQL, data migration, job replay).
  def same_account?(assistant, conversation)
    return true if assistant.account_id == conversation.account_id

    Rails.logger.error(
      "[Athenas autopilot] cross-account guard tripped: assistant=#{assistant.id} " \
      "(account #{assistant.account_id}) vs conversation=#{conversation.id} " \
      "(account #{conversation.account_id}); aborting"
    )
    false
  end

  # Two-phase reply so the Claude/belezaki HTTP round-trip never runs while a DB
  # row lock is held (that used to pin a Postgres connection for the whole call,
  # choking the pool under load):
  #   1. cheap lock-free pre-check to bail early on retries / throttling;
  #   2. generate the reply with NO lock held;
  #   3. a SHORT locked transaction that re-checks (a concurrent job may have
  #      answered meanwhile) and then writes the outgoing message + dedup stamp.
  def deliver_reply(conversation, assistant, message)
    return if already_replied_to?(conversation, message.id)
    return if superseded?(conversation, message.id)
    return if outrun?(conversation, message)
    return if rate_limited?(conversation, assistant)

    reply_text = generate_reply_text(conversation, assistant, message)
    return mark_delivery_failed!(conversation, assistant.id, message.id, handoff: false) if reply_text.blank?

    commit_reply(conversation, assistant, message, reply_text)
  end

  def commit_reply(conversation, assistant, message, reply_text)
    committed = false
    sent = nil
    Conversation.transaction do
      # lock! reloads under SELECT ... FOR UPDATE, so the re-checks below see a
      # concurrent job's write and we never post twice for the same trigger.
      conversation.lock!
      next if already_replied_to?(conversation, message.id)
      next if superseded?(conversation, message.id)
      next if rate_limited?(conversation, assistant)

      sent = send_outgoing(conversation, assistant, reply_text)
      link_invocation(conversation, assistant, message, sent)
      mark_replied!(conversation, message.id)
      record_reply_rate!(conversation)
      log_turn_complete(conversation, message)
      committed = true
    end
    # Outside the lock on purpose: projecting the capped Histórico row must never
    # extend the transaction that holds the conversation, and its failure must
    # never cost the reply that already went out (see Ai::ResponseHistoryRecorder).
    Ai::ResponseHistoryRecorder.record!(assistant: assistant, conversation: conversation, message: sent) if committed
    # A reply that was generated and then dropped by the in-lock re-check still
    # exists in the log. Closing it out is what makes "pending" mean "generated
    # but never accounted for" instead of ordinary noise.
    mark_delivery_failed!(conversation, assistant.id, message.id, handoff: false) unless committed
  end

  # A LATER message in this conversation was already answered, so this turn is
  # stale — typical after a retry, or when the customer fired a burst. Replying
  # now would push an answer to a question the bot already moved past.
  def superseded?(conversation, message_id)
    last_replied = conversation.additional_attributes.to_h['autopilot_last_replied_message_id']
    last_replied.present? && last_replied.to_i > message_id.to_i
  end

  # Another message from the customer landed while this turn sat in the debounce
  # window, so this turn stands down: the newer message has a turn of its own,
  # and it will answer the whole burst at once.
  #
  # Without this, three messages in five seconds bought three Claude calls and
  # sent the customer three replies — neither `already_replied_to?` (exact match
  # on the trigger id) nor `superseded?` (a LATER message already answered)
  # catches an EARLIER message being answered after this one.
  #
  # Checked before generating and NOT again inside the lock, on purpose. Once a
  # reply exists it has been paid for and still answers what was asked; a
  # message that arrived mid-generation gets its own turn, the way a person
  # finishes their sentence before reading the next one.
  def outrun?(conversation, message)
    return false unless conversation.messages.where(message_type: :incoming).exists?(['id > ?', message.id])

    Rails.logger.info(
      "[Athenas autopilot] standing down, newer message arrived conv=#{conversation.display_id} message=#{message.id}"
    )
    true
  end

  # End-to-end turn latency: what the CUSTOMER actually waited, queue time and
  # retries included. Per-call model latency/tokens/cost already land on
  # Ai::Invocation; this is the number that per-call timing can't show.
  def log_turn_complete(conversation, message)
    latency_ms = ((Time.current - message.created_at) * 1000).to_i
    Rails.logger.info(
      "[Athenas autopilot] turn complete conv=#{conversation.display_id} " \
      "message=#{message.id} attempt=#{executions} latency_ms=#{latency_ms}"
    )
  end

  def generate_reply_text(conversation, assistant, message)
    result = Ai::AutopilotReplyService.new(
      conversation: conversation, assistant: assistant, trigger_message: message
    ).perform
    result[:content].to_s.strip
  end

  # Returns the LAST message created. The invocation log is stamped with that
  # id, and the history row reads its text from the invocation rather than the
  # message, so a split reply still shows whole in supervision.
  def send_outgoing(conversation, assistant, reply_text)
    quoted = quote_attributes(conversation, assistant)
    reply_parts(assistant, reply_text).each_with_index.map do |part, index|
      params = { content: part, message_type: :outgoing }
      # Only the first bubble quotes. WhatsApp renders one quoted header per
      # message, so four bubbles all citing the same question is noise.
      params[:content_attributes] = quoted if index.zero? && quoted.present?
      Messages::MessageBuilder.new(assistant_user(assistant), conversation, params).perform
    end.last
  end

  # The customer's question, quoted above the answer — the WhatsApp reply arrow.
  #
  # Keyed on `in_reply_to_external_id`, NOT `in_reply_to`, and that is load
  # bearing: Messages::MessageBuilder only reads `in_reply_to` out of
  # content_attributes when the params are ActionController::Parameters, then
  # assigns the resulting nil back over the key through the store accessor. On
  # this (plain Hash) path that would wipe the quote on its way to the database.
  # The external id survives, and Message#ensure_in_reply_to resolves the pair
  # back from it — scoped to this conversation, so it cannot cite another
  # tenant's message.
  def quote_attributes(conversation, assistant)
    return {} unless assistant.behavior_flag?(:reply_marking)

    quoted = message_worth_quoting(conversation)
    # No source_id on channels that carry no provider id (playground, API
    # inbox); there is nothing to quote and the builder would no-op anyway.
    return {} if quoted.nil? || quoted.source_id.blank?

    { in_reply_to_external_id: quoted.source_id }
  end

  # A quote on every single reply is a nervous tic, not a courtesy: in an
  # ordinary back-and-forth ("quanto custa?" → "R$ 299" → "ok, vou levar") there
  # is only one thing the answer could possibly be about, and the arrow adds
  # nothing but clutter. People quote on WhatsApp for exactly two reasons, and
  # these are those two:
  #
  #   - the customer fired several messages before anyone answered, so the reply
  #     has to say WHICH one it picked up;
  #   - the answer arrives long after the question, by which time the customer
  #     has scrolled away and needs re-anchoring.
  #
  # Anything else stays quiet.
  # A question mark, or one of the words a question opens with when the customer
  # cannot be bothered to type one — which on WhatsApp is most of the time.
  # Deliberately conservative: missing a question costs a quote nobody notices,
  # while quoting a statement is the tic the operator objected to.
  QUESTION = /
    \?
    |\A\s*(?:qual|quais|quanto|quantos|quantas|quando|onde|como|quem
            |por\s*qu[eê]|porqu[eê]|t[eê]m|teria|aceita|aceitam
            |consegue|conseguem|d[aá]\s+pra)\b
  /xi

  # Which message the arrow points at, or nil when it points at nothing.
  #
  # The QUESTION, which is what the toggle is named after. Not every message:
  # answering "ok, vou levar" with a quote is a nervous tic. A question is
  # exactly where the arrow earns its place — and it keeps earning it when a
  # burst arrives, because then the answer covers several messages at once and
  # has to say which one it picked up.
  #
  # Oldest first, so a burst quotes the question it starts from rather than the
  # fragment that happened to trigger the turn ("...aquela de 1L").
  def message_worth_quoting(conversation)
    unanswered_incoming(conversation).find { |message| QUESTION.match?(message.content.to_s) }
  end

  # Customer messages piled up since the last thing anyone sent them. Runs
  # inside the conversation lock and before this turn's own reply is written,
  # so "last outgoing" is genuinely the previous answer. Private notes are
  # excluded: a human's internal note is invisible to the customer, so it never
  # counts as having replied to them.
  MAX_PENDING_SCANNED = 10

  def unanswered_incoming(conversation)
    last_reply_id = conversation.messages.where(message_type: :outgoing, private: false).maximum(:id).to_i
    conversation.messages.where(message_type: :incoming).where('id > ?', last_reply_id)
                .order(:id).limit(MAX_PENDING_SCANNED).to_a
  end

  # One bubble per paragraph, the way a person types on WhatsApp, when the
  # operator asked for it. Off by default: an agent that suddenly fires four
  # notifications instead of one is a behaviour change the tenant has to choose.
  #
  # No pause between them, deliberately. This runs inside the conversation row
  # lock (see #commit_reply), so sleeping here would hold that lock — and a
  # Sidekiq thread — for the whole performance. Separate bubbles are the win;
  # simulated typing delay is not worth starving the queue for.
  def reply_parts(assistant, reply_text)
    text = reply_text.to_s
    return [text] unless assistant.behavior_flag?(:split_messages)
    # A short answer is one thought however many line breaks the model put in
    # it. Cutting "R$ 219,00" and "quer que eu mande o link?" into two bubbles
    # buys the customer a second notification and no extra meaning.
    return [text] if text.length < SPLIT_FLOOR_CHARS

    parts = split_on_paragraphs(text)
    parts.length > 1 ? parts : [text]
  end

  # Blank lines are where the model already breaks its own thought. Fragments
  # shorter than MIN_PART_CHARS are glued to the previous bubble — "Claro!" on
  # its own line is punctuation, not a message — and everything past MAX_PARTS
  # collapses into the last one so a long answer cannot become a burst.
  # Tuned down from 4 bubbles and a 12-character floor, which in production
  # turned a single answer into four notifications: "Quer que eu mande o link?"
  # is 25 characters and was clearing the old floor comfortably.
  #
  # MAX_PARTS matches what the prompt already asks the model for ("no máximo 3
  # parágrafos"), so the ceiling and the instruction finally agree. A bubble
  # under MIN_PART_CHARS is a fragment, not a message, and gets glued to the one
  # before it. Below SPLIT_FLOOR_CHARS the whole reply stays in one bubble.
  MAX_PARTS = 3
  MIN_PART_CHARS = 40
  SPLIT_FLOOR_CHARS = 160

  def split_on_paragraphs(text)
    chunks = text.split(/\n{2,}/).map(&:strip).reject(&:blank?)
    return chunks if chunks.length <= 1

    chunks.each_with_object([]) do |chunk, acc|
      if acc.empty? || keep_separate?(acc, chunk)
        acc << chunk
      else
        acc[-1] = "#{acc.last}\n\n#{chunk}"
      end
    end
  end

  # A paragraph earns its own bubble only when BOTH it and the one before it are
  # long enough to read as messages, and the burst cap still has room. Checking
  # the previous one matters: a greeting arriving first has nothing behind it to
  # be glued to, and would otherwise ship as a bubble of its own.
  def keep_separate?(acc, chunk)
    chunk.length >= MIN_PART_CHARS && acc.last.length >= MIN_PART_CHARS && acc.length < MAX_PARTS
  end

  # Ties the reply the customer actually received back to the invocations that
  # produced it. The column existed but was never filled, so the history screen
  # had cost and latency with no way to show WHAT was said.
  #
  # ALL calls of this turn are linked, not just the last one: a turn that used
  # the scheduling tools bills several Claude calls, and linking only the final
  # one would report a fraction of what the answer really cost. Scoped by
  # trigger message, so a neighbouring turn's rows can never be swept in — and
  # restricted to rows still awaiting delivery, so a row already closed as a
  # handoff is never relabelled as delivered.
  # Best-effort: a missing link costs a row in a report, never the reply.
  def link_invocation(conversation, assistant, message, sent)
    return if sent.blank?

    # rubocop:disable Rails/SkipsModelValidations
    turn_invocations(conversation, assistant.id, message.id)
      .awaiting_delivery.update_all(message_id: sent.id, delivery_status: 'sent')
    # rubocop:enable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn("[Athenas autopilot] could not link invocation to message: #{e.message}")
  end

  def mark_delivery_failed!(conversation, assistant_id, message_id, handoff:)
    self.class.close_out_turn!(conversation, assistant_id, message_id, handoff: handoff)
  end

  def turn_invocations(conversation, assistant_id, message_id)
    self.class.turn_invocations(conversation, assistant_id, message_id)
  end

  # Redis sliding-window over the bot's own replies (recorded on send), so the
  # hot-path check never touches Postgres. Falls back to a DB COUNT if Redis is
  # unreachable, so a Redis hiccup can never silently drop the guardrail.
  def rate_limited?(conversation, assistant)
    reply_rate_limiter(conversation, assistant).exceeded?
  rescue StandardError => e
    Rails.logger.warn("[Athenas autopilot] Redis rate-limit unavailable (#{e.message}); DB fallback")
    rate_limited_via_db?(conversation, assistant)
  end

  # Best-effort: records this reply in the sliding window. Never breaks the send
  # (the reply already went out) if Redis is momentarily unavailable. Hits made
  # during a Redis outage aren't recorded, so the minute spanning a recovery can
  # allow a one-time overage before the window refills — acceptable for a soft
  # chattiness limiter (the row lock + message-id dedup guarantee correctness
  # independently of this counter).
  def record_reply_rate!(conversation)
    reply_rate_limiter(conversation, nil).record!
  rescue StandardError => e
    Rails.logger.warn("[Athenas autopilot] Redis rate-limit record failed (#{e.message})")
  end

  def reply_rate_limiter(conversation, assistant)
    Redis::SlidingWindowRateLimiter.new(
      format(Redis::RedisKeys::AUTOPILOT_REPLY_RATE, conversation_id: conversation.id),
      limit: reply_limit(assistant),
      window: RATE_LIMIT_WINDOW.to_i
    )
  end

  # `limit` is only consulted by `exceeded?`, never by `record!`, so a nil
  # assistant on the record path is fine (falls back to the default).
  def reply_limit(assistant)
    guardrails = assistant&.guardrails
    (guardrails.is_a?(Hash) ? guardrails['max_messages_per_minute'] : nil) || 4
  end

  # Redis-outage fallback. Intentionally conservative: it counts ALL outgoing
  # (not only the bot replies the Redis window tracks), so during an outage we
  # err toward silence rather than risk spamming. Fail-safe by construction —
  # bot replies are a subset of outgoing, so this can only throttle more, never
  # let the bot exceed the cap.
  def rate_limited_via_db?(conversation, assistant)
    sent_recently = conversation.messages
                                .where(message_type: :outgoing)
                                .where('created_at > ?', RATE_LIMIT_WINDOW.ago)
                                .count
    sent_recently >= reply_limit(assistant)
  end

  # Idempotency for the reply itself: a retried job (Sidekiq re-run after the
  # lock was released, e.g. a failure downstream of send_outgoing) must not post
  # a second reply to the same trigger message. We stamp the trigger id on the
  # conversation inside the SAME locked transaction as the outgoing message, so
  # a retry reads it and bails.
  def already_replied_to?(conversation, message_id)
    conversation.additional_attributes.to_h['autopilot_last_replied_message_id'] == message_id
  end

  def mark_replied!(conversation, message_id)
    attrs = conversation.additional_attributes.to_h.merge('autopilot_last_replied_message_id' => message_id)
    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_column(:additional_attributes, attrs)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # Who the reply comes FROM. Chatwoot's own concept for a non-human sender, so
  # everything that labels a message by its sender names the agent instead of
  # falling back to the raw chat id: the dashboard, and the WhatsApp bridge that
  # writes "Taina Iris:" above a human agent's reply and was writing
  # "553185900095@c.us:" above the bot's.
  #
  # Nil until the operator names the agent, which is how every reply has been
  # sent until now — an unnamed agent keeps going out anonymous rather than
  # silently acquiring an identity nobody chose.
  def assistant_user(assistant)
    name = assistant.conversation_display_name.to_s.strip
    return nil if name.blank?

    @assistant_user ||= bot_for(assistant, name)
  end

  # One bot per assistant, keyed by the assistant id kept in bot_config, and
  # RENAMED in place when the operator edits the field. Creating a new one per
  # name would leave a graveyard behind and, worse, would relabel nothing —
  # messages already sent keep pointing at the bot that sent them.
  #
  # Scoped to the assistant's own account on both the lookup and the insert, so
  # one workspace's agent can never end up speaking as another's.
  def bot_for(assistant, name)
    bot = AgentBot.where(account_id: assistant.account_id)
                  .where('bot_config @> ?', { ai_assistant_id: assistant.id }.to_json).first
    return create_bot(assistant, name) if bot.nil?

    bot.update!(name: name) unless bot.name == name
    bot
  end

  def create_bot(assistant, name)
    AgentBot.create!(
      account_id: assistant.account_id,
      name: name,
      description: "Agente Athenas ##{assistant.id}",
      bot_config: { 'ai_assistant_id' => assistant.id }
    )
  end
end
# rubocop:enable Metrics/ClassLength
