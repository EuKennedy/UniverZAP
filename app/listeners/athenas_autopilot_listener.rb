# Listens to message_created events and enqueues an autopilot reply job
# whenever the inbox (or the conversation override) is in autopilot mode and
# an active Athenas assistant is wired to the inbox.
class AthenasAutopilotListener < BaseListener
  def message_created(event)
    message, = extract_message_and_account(event)
    # Runs before the eligibility gate: a customer complaining about a past
    # reply is worth logging even on a conversation where autopilot is now off.
    audit_customer_signal(message)
    return log_skip(:not_eligible, message) unless eligible?(message)

    conversation = message.conversation
    assistant = resolve_assistant(conversation)
    return log_skip(:no_assistant, message) if assistant.blank?
    return log_skip(:inactive_assistant, message, assistant) unless assistant.active?
    return log_skip(:group_conversation, message, assistant) if assistant.skip_groups? && conversation.is_group?
    return log_skip(:guardrail, message, assistant) if guardrail_triggered?(message, assistant)

    Rails.logger.info(
      "[Athenas autopilot] enqueue job conv=#{conversation.id} message=#{message.id} assistant=#{assistant.id}"
    )
    Ai::AutopilotReplyJob.set(wait: Ai::AutopilotReplyJob::DEBOUNCE_WINDOW).perform_later(message.id, assistant.id)
  end

  # A conversation that closes without a sale is the moment the commercial
  # radar has something to say. Scoring it here rather than on a nightly sweep
  # means the follow-up window is still open when the lead surfaces: an
  # interested customer answered twenty minutes ago, not yesterday.
  def conversation_resolved(event)
    conversation = event.data[:conversation]
    return if conversation.blank? || conversation.sandbox?
    return unless scored_by_an_agent?(conversation)

    Ai::LeadScoringJob.perform_later(conversation.id)
  rescue StandardError => e
    Rails.logger.warn("[Athenas radar] scoring not enqueued conv=#{conversation&.id}: #{e.message}")
  end

  private

  # Only conversations the agent actually worked. Scoring a thread it never
  # touched would credit the radar with leads it had nothing to do with.
  def scored_by_an_agent?(conversation)
    Ai::Invocation.exists?(conversation_id: conversation.id, phase: 'autopilot')
  end

  # The strongest quality signal the module gets, and the only one that arrives
  # a turn late. The pattern match is pure Ruby and runs on every inbound
  # message; a worker is only involved when it actually matches, so the common
  # case costs nothing.
  def audit_customer_signal(message)
    return if message.blank? || !message.incoming? || message.private?
    return unless Ai::Guardrails::CustomerSignal.dissatisfied?(message.content)

    Ai::CustomerSignalAuditJob.perform_later(message.id)
  rescue StandardError => e
    Rails.logger.warn("[Athenas] customer signal audit not enqueued: #{e.message}")
  end

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

  # Three ways autopilot can be on, in the order an operator expects them to
  # win.
  def resolve_assistant(conversation)
    attrs = conversation.additional_attributes || {}

    # 1. Silenced on THIS conversation. The only override that beats the agent's
    #    own switch, and it has to: it is how an operator takes over when the
    #    customer asks for a human. Without it there is no way to stop the bot
    #    in one conversation short of switching it off for everybody.
    return nil if silenced?(attrs)

    # 2. Switched on for THIS conversation (the "ligar IA neste chat" button).
    #    Lives in additional_attributes (jsonb) rather than the `ai_mode`
    #    column, which resolve / assign / reopen silently reset — that drift is
    #    why an operator once saw "IA ligada" and the wrong path fired.
    return resolve_toggled_assistant(conversation, attrs) if enabled?(attrs)

    # 3. The agent's own autopilot switch. Marking it means the agent answers
    #    wherever it is assigned, without the operator having to arm every
    #    conversation or the inbox by hand — which is what the checkbox has
    #    always said it did.
    assistant = assigned_assistant(conversation)
    return assistant if assistant&.autopilot?

    inbox_wide_assistant(conversation, assistant)
  end

  def silenced?(attrs)
    attrs.key?('autopilot_enabled') && !ActiveModel::Type::Boolean.new.cast(attrs['autopilot_enabled'])
  end

  def enabled?(attrs)
    attrs.key?('autopilot_enabled') && ActiveModel::Type::Boolean.new.cast(attrs['autopilot_enabled'])
  end

  def assigned_assistant(conversation)
    conversation.ai_assistant || conversation.inbox.ai_assistant
  end

  # Inbox-wide mode, for accounts that drive autopilot there instead of on the
  # agent. Kept so nothing that worked before stops working.
  def inbox_wide_assistant(conversation, assistant)
    mode = conversation.ai_mode.presence || conversation.inbox.ai_mode
    return nil unless mode == 'autopilot'

    assistant
  end

  def resolve_toggled_assistant(conversation, attrs)
    conversation.ai_assistant ||
      find_account_assistant(conversation, attrs['autopilot_assistant_id']) ||
      conversation.inbox.ai_assistant
  end

  def find_account_assistant(conversation, assistant_id)
    return nil if assistant_id.blank?

    conversation.account.ai_assistants.find_by(id: assistant_id)
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
