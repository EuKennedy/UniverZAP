# Listens to message_created events and enqueues an autopilot reply job
# whenever the inbox (or the conversation override) is in autopilot mode and
# an active Athenas assistant is wired to the inbox.
class AthenasAutopilotListener < BaseListener
  def message_created(event)
    message, = extract_message_and_account(event)
    return log_skip(:not_eligible, message) unless eligible?(message)

    conversation = message.conversation
    assistant = resolve_assistant(conversation)
    return log_skip(:no_assistant, message) if assistant.blank?
    return log_skip(:inactive_assistant, message, assistant) unless assistant.active?
    return log_skip(:guardrail, message, assistant) if guardrail_triggered?(message, assistant)

    Rails.logger.info(
      "[Athenas autopilot] enqueue job conv=#{conversation.id} message=#{message.id} assistant=#{assistant.id}"
    )
    Ai::AutopilotReplyJob.perform_later(message.id, assistant.id)
  end

  private

  def eligible?(message)
    return false if message.blank?
    return false unless message.incoming?
    return false if message.private?

    true
  end

  def log_skip(reason, message, assistant = nil)
    Rails.logger.info(
      "[Athenas autopilot] skipped reason=#{reason} " \
      "conv=#{message&.conversation_id} message=#{message&.id} assistant=#{assistant&.id}"
    )
    nil
  end

  def resolve_assistant(conversation)
    mode = conversation.ai_mode.presence || conversation.inbox.ai_mode
    return nil unless mode == 'autopilot'

    conversation.ai_assistant || conversation.inbox.ai_assistant
  end

  def guardrail_triggered?(message, assistant)
    stop_words = assistant.guardrails.is_a?(Hash) ? Array(assistant.guardrails['stop_words']) : []
    return false if stop_words.empty?

    body = message.content.to_s.downcase
    matched = stop_words.find { |word| body.include?(word.to_s.downcase) }
    return false unless matched

    # Emit a single log line per trigger so security/compliance can see
    # exactly which stop word silenced the autopilot for which message.
    Rails.logger.info(
      "[Athenas guardrail] stop_word=#{matched.inspect} silenced autopilot " \
      "assistant=#{assistant.id} message=#{message.id} conversation=#{message.conversation_id}"
    )
    true
  end
end
