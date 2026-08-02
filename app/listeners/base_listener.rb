class BaseListener
  include Singleton

  # True for an Athenas test-playground event. The sandbox runs the production
  # agent over a real Conversation on purpose (fidelity), which means it also
  # emits real events — so every listener with an OUTWARD side effect (customer
  # webhooks, automation actions, chatflow) must opt out of them explicitly.
  def sandbox_event?(event)
    conversation = event.data[:conversation] || event.data[:message]&.conversation
    return true if conversation.respond_to?(:sandbox?) && conversation.sandbox?

    # Contact events carry no conversation, so the sandbox contact is stamped
    # directly (it would otherwise be published as a real new contact).
    contact = event.data[:contact]
    contact.respond_to?(:custom_attributes) && contact.custom_attributes.to_h['athenas_sandbox'].present?
  end

  def extract_conversation_and_account(event)
    conversation = event.data[:conversation]
    [conversation, conversation.account]
  end

  def extract_notification_and_account(event)
    notification = event.data[:notification]
    notification_finder = NotificationFinder.new(notification.user, notification.account)
    unread_count = notification_finder.unread_count
    count = notification_finder.count
    [notification, notification.account, unread_count, count]
  end

  def extract_message_and_account(event)
    message = event.data[:message]
    [message, message.account]
  end

  def extract_contact_and_account(event)
    contact = event.data[:contact]
    [contact, contact.account]
  end

  def extract_inbox_and_account(event)
    inbox = event.data[:inbox]
    [inbox, inbox.account]
  end

  def extract_changed_attributes(event)
    changed_attributes = event.data[:changed_attributes]

    return if changed_attributes.blank?

    changed_attributes.map { |k, v| { k => { previous_value: v[0], current_value: v[1] } } }
  end
end
