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

  def rate_limited?(conversation, assistant)
    limit = (assistant.guardrails.is_a?(Hash) ? assistant.guardrails['max_messages_per_minute'] : nil) || 4
    sent_recently = conversation.messages
                                .where(message_type: :outgoing)
                                .where('created_at > ?', RATE_LIMIT_WINDOW.ago)
                                .count
    sent_recently >= limit
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
