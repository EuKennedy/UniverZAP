# Labels a new conversation of a returning customer as soon as it exists.
# Runs before the automation listener in the dispatcher, so a
# `conversation_created` rule already sees the `cliente-recorrente` label and
# a `conversation.recurring_customer` rule gets its own event.
class RecurringCustomerListener < BaseListener
  def conversation_created(event)
    return if sandbox_event?(event)

    conversation = event.data[:conversation]
    return if conversation.blank?

    Conversations::RecurringCustomerService.new(conversation).perform
  end
end
