class Ai::AutopilotReplyJob < ApplicationJob
  queue_as :default

  RATE_LIMIT_WINDOW = 1.minute

  def perform(message_id, assistant_id)
    message = Message.find_by(id: message_id)
    assistant = Ai::Assistant.find_by(id: assistant_id)
    return unless message && assistant

    conversation = message.conversation
    return unless same_account?(assistant, conversation)

    with_tenant_context(conversation) do
      deliver_reply(conversation, assistant, message_id)
    end
  rescue Ai::AutopilotReplyService::LoopSuppressed => e
    # Intentional silence: the reply would have repeated a recent turn.
    # Logged at info — this is the loop-breaker working as designed.
    Rails.logger.info("[Athenas autopilot] #{e.message}")
  rescue Ai::ClaudeService::Error => e
    Rails.logger.error("[Athenas autopilot] failed for message=#{message_id}: #{e.message}")
  end

  private

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
  def deliver_reply(conversation, assistant, message_id)
    return if already_replied_to?(conversation, message_id)
    return if rate_limited?(conversation, assistant)

    reply_text = generate_reply_text(conversation, assistant)
    return if reply_text.blank?

    commit_reply(conversation, assistant, message_id, reply_text)
  end

  def commit_reply(conversation, assistant, message_id, reply_text)
    Conversation.transaction do
      # lock! reloads under SELECT ... FOR UPDATE, so the re-checks below see a
      # concurrent job's write and we never post twice for the same trigger.
      conversation.lock!
      next if already_replied_to?(conversation, message_id)
      next if rate_limited?(conversation, assistant)

      send_outgoing(conversation, assistant, reply_text)
      mark_replied!(conversation, message_id)
      record_reply_rate!(conversation)
    end
  end

  def generate_reply_text(conversation, assistant)
    result = Ai::AutopilotReplyService.new(conversation: conversation, assistant: assistant).perform
    result[:content].to_s.strip
  end

  def send_outgoing(conversation, assistant, reply_text)
    Messages::MessageBuilder.new(
      assistant_user(assistant),
      conversation,
      content: reply_text,
      message_type: :outgoing
    ).perform
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

  def assistant_user(_assistant)
    # Outgoing messages without a sender stay anonymous on the API channel; this
    # mirrors how WAHA injects bot replies via the Chatwoot API.
    nil
  end
end
