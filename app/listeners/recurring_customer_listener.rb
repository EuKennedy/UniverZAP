# Labels the conversation of a returning customer as soon as the return is
# visible: when the conversation is created (the contact already had another
# conversation that ended) and on every message the contact sends (the same
# conversation was resolved before and is being reopened — the WAHA bridge
# keeps one conversation per contact). Runs before the automation listener in
# the dispatcher, so a `conversation_created` rule already sees the
# `cliente-recorrente` label and a `conversation.recurring_customer` rule gets
# its own event. The service is idempotent, so a first message running through
# both hooks labels once and fires once.
class RecurringCustomerListener < BaseListener
  def conversation_created(event)
    return if sandbox_event?(event)

    conversation = event.data[:conversation]
    return if conversation.blank?

    Conversations::RecurringCustomerService.new(conversation).perform
  end

  def message_created(event)
    return if sandbox_event?(event)

    message = event.data[:message]
    return if message.blank? || !message.incoming? || message.private?

    Conversations::RecurringCustomerService.new(message.conversation).perform
  end
end
