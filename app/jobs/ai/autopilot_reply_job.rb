class Ai::AutopilotReplyJob < ApplicationJob
  queue_as :default

  RATE_LIMIT_WINDOW = 1.minute

  def perform(message_id, assistant_id)
    message = Message.find_by(id: message_id)
    assistant = Ai::Assistant.find_by(id: assistant_id)
    return unless message && assistant

    conversation = message.conversation

    # Defense-in-depth tenant guard: never let an assistant from another account
    # answer this conversation, even if a cross-account ai_assistant_id somehow
    # slipped past the model validation (raw SQL, data migration, job replay).
    unless assistant.account_id == conversation.account_id
      Rails.logger.error(
        "[Athenas autopilot] cross-account guard tripped: assistant=#{assistant.id} " \
        "(account #{assistant.account_id}) vs conversation=#{conversation.id} " \
        "(account #{conversation.account_id}); aborting"
      )
      return
    end

    # NOTE: the listener already gated on ai_mode='autopilot'. Autopilot
    # intentionally overrides a human assignee when the conversation opted in.
    #
    # Wrap the rate-limit check + outgoing message in a single transaction
    # with a row lock on the conversation. Without the lock, two concurrent
    # jobs (e.g. two inbound messages within the same window) can both pass
    # the count check before either has written its reply, blowing past
    # `max_messages_per_minute` and triggering the loop-prevention rules
    # downstream. Using nested ifs instead of `return` so rubocop's
    # Rails/TransactionExitStatement stays happy (a bare return inside a
    # transaction silently commits with whatever side-effects already ran).
    Conversation.transaction do
      conversation.lock!
      next if rate_limited?(conversation, assistant)

      reply_text = generate_reply_text(conversation, assistant)
      next if reply_text.blank?

      send_outgoing(conversation, assistant, reply_text)
    end
  rescue Ai::AutopilotReplyService::LoopSuppressed => e
    # Intentional silence: the reply would have repeated a recent turn.
    # Logged at info — this is the loop-breaker working as designed.
    Rails.logger.info("[Athenas autopilot] #{e.message}")
  rescue Ai::ClaudeService::Error => e
    Rails.logger.error("[Athenas autopilot] failed for message=#{message_id}: #{e.message}")
  end

  private

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

  def assistant_user(_assistant)
    # Outgoing messages without a sender stay anonymous on the API channel; this
    # mirrors how WAHA injects bot replies via the Chatwoot API.
    nil
  end
end
