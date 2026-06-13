# Sends one broadcast recipient in WAHA mode. The outgoing message is created
# through Messages::MessageBuilder — exactly like Chatflow::NodeRunnerService —
# so it renders in the Chatwoot timeline AND dispatches to WhatsApp via WAHA.
# Never raises: a single bad recipient is marked failed and the batch goes on.
class Broadcasts::RecipientSenderService
  def initialize(recipient)
    @recipient = recipient
    @broadcast = recipient.broadcast
    @contact = recipient.contact
    @inbox = @broadcast.inbox
  end

  def perform
    return mark_failed('missing phone_number') if @contact.phone_number.blank?

    conversation = find_or_create_conversation
    send_message(conversation)

    @recipient.update!(status: :sent, sent_at: Time.current, conversation_id: conversation.display_id)
  rescue StandardError => e
    Rails.logger.error("[Broadcast send] recipient=#{@recipient.id} #{e.message}")
    mark_failed(e.message)
  end

  private

  def find_or_create_conversation
    contact_inbox = find_or_build_contact_inbox
    contact_inbox.conversations.last || ::Conversation.create!(
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: contact_inbox.id
    )
  end

  def find_or_build_contact_inbox
    existing = ContactInbox.find_by(contact_id: @contact.id, inbox_id: @inbox.id)
    return existing if existing

    ::ContactInboxWithContactBuilder.new(
      source_id: @contact.phone_number.delete('+'),
      inbox: @inbox,
      contact_attributes: { name: @contact.name, phone_number: @contact.phone_number }
    ).perform
  end

  def send_message(conversation)
    params = { content: @broadcast.message_text, message_type: 'outgoing' }
    Messages::MessageBuilder.new(nil, conversation, params).perform
  end

  def mark_failed(message)
    @recipient.update!(status: :failed, error: message)
  end
end
