class Ai::AutopilotReplyJob < ApplicationJob
  queue_as :default

  RATE_LIMIT_WINDOW = 1.minute

  def perform(message_id, assistant_id)
    message = Message.find_by(id: message_id)
    assistant = Ai::Assistant.find_by(id: assistant_id)
    return unless message && assistant

    conversation = message.conversation
    return if conversation.assignee_id.present?
    return if rate_limited?(conversation, assistant)

    result = Ai::SuggestReplyService.new(conversation: conversation, assistant: assistant).perform
    reply_text = result[:content].to_s.strip
    return if reply_text.blank?

    Messages::MessageBuilder.new(
      assistant_user(assistant),
      conversation,
      content: reply_text,
      message_type: :outgoing
    ).perform
  rescue Ai::ClaudeService::Error => e
    Rails.logger.error("[Athenas autopilot] failed for message=#{message_id}: #{e.message}")
  end

  private

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
