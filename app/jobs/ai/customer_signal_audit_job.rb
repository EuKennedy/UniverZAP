# Flags the agent reply that a customer has just pushed back on.
#
# Runs one turn late by nature: the signal only exists after the customer
# answers. Enqueued from AthenasAutopilotListener only when the inbound text
# already matches the dissatisfaction pattern, so the common case never reaches
# a worker at all.
class Ai::CustomerSignalAuditJob < ApplicationJob
  queue_as :low

  # How far back a reply can be and still plausibly be what the customer is
  # reacting to. Beyond this the complaint is about something else.
  LOOKBACK = 2.hours

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank? || message.conversation&.sandbox?
    return unless Ai::Guardrails::CustomerSignal.dissatisfied?(message.content)

    invocation = preceding_reply(message)
    return if invocation.blank?

    flag!(invocation, message)
  end

  private

  # The agent reply this message is reacting to.
  #
  # Anchored on the LAST outgoing message, not on the last logged call. A human
  # operator routinely takes over mid-conversation; if they answered after the
  # bot did, the complaint is about the human, and blaming the bot's earlier
  # reply would poison the queue with the one thing it must never contain — a
  # correct answer marked wrong.
  def preceding_reply(message)
    last_outgoing = message.conversation.messages
                           .where(message_type: :outgoing, private: false)
                           .where(messages: { created_at: ...message.created_at })
                           .reorder(created_at: :desc, id: :desc)
                           .first
    return nil if last_outgoing.blank?

    Ai::Invocation.where(conversation_id: message.conversation_id, message_id: last_outgoing.id)
                  .where(created_at: LOOKBACK.ago..)
                  .order(created_at: :desc)
                  .first
  end

  def flag!(invocation, message)
    flags = (Array(invocation.auto_flags) + ['cliente_insatisfeito']).uniq
    invocation.update!(auto_flags: flags, auto_flag: Ai::Invocation.primary_flag(flags))
    Rails.logger.info(
      "[Athenas guardrails] cliente_insatisfeito invocation=#{invocation.id} " \
      "triggered_by_message=#{message.id}"
    )
  rescue StandardError => e
    # An audit annotation is never worth failing a job over.
    Rails.logger.warn("[Athenas guardrails] could not flag customer signal: #{e.message}")
  end
end
