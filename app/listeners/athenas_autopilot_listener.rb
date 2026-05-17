# Listens to message_created events and enqueues an autopilot reply job
# whenever the inbox (or the conversation override) is in autopilot mode and
# an active Athenas assistant is wired to the inbox.
class AthenasAutopilotListener < BaseListener
  def message_created(event)
    message, = extract_message_and_account(event)
    return unless eligible?(message)

    conversation = message.conversation
    assistant = resolve_assistant(conversation)
    return unless assistant&.active? && assistant.autopilot_enabled?
    return if guardrail_triggered?(message, assistant)

    Ai::AutopilotReplyJob.perform_later(message.id, assistant.id)
  end

  private

  def eligible?(message)
    return false if message.blank?
    return false unless message.incoming?
    return false if message.private?

    true
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
    stop_words.any? { |word| body.include?(word.to_s.downcase) }
  end
end
