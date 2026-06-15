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

    @broadcast.mode == 'official' ? send_official : send_waha
  rescue StandardError => e
    Rails.logger.error("[Broadcast send] recipient=#{@recipient.id} #{e.message}")
    mark_failed(e.message)
  end

  private

  # WAHA (unofficial): build the message through Messages::MessageBuilder so it
  # renders in Chatwoot AND ships via the WAHA connector.
  def send_waha
    conversation = find_or_create_conversation
    send_message(conversation)
    @recipient.update!(status: :sent, sent_at: Time.current, conversation_id: conversation.display_id)
  end

  # Official (Meta Cloud API): send an approved template, reusing Chatwoot's
  # existing template machinery (same path as Whatsapp::OneoffCampaignService).
  def send_official
    channel = @inbox.channel
    raise 'official mode needs a WhatsApp Cloud inbox' unless channel.respond_to?(:send_template)

    template_params = personalized_template_params
    raise 'missing template config' if template_params.blank?

    name, namespace, lang_code, parameters = Whatsapp::TemplateProcessorService.new(
      channel: channel, template_params: template_params, message: nil
    ).call
    raise 'template not resolved' if name.blank?

    channel.send_template(@contact.phone_number,
                          { name: name, namespace: namespace, lang_code: lang_code, parameters: parameters }, nil)
    @recipient.update!(status: :sent, sent_at: Time.current)
  end

  # Per-recipient copy of the template config with contact tokens resolved.
  # Tokens like `{contact.name}`, `{contact.phone_number}`, `{contact.email}`
  # or `{contact.attr.KEY}` are replaced with this contact's values so each
  # recipient gets a personalized template. Deep-duped so recipients never
  # bleed into each other.
  def personalized_template_params
    raw = @broadcast.message['template']
    return raw if raw.blank?

    resolve_tokens(Marshal.load(Marshal.dump(raw)))
  end

  def resolve_tokens(node)
    case node
    when Hash then node.transform_values { |v| resolve_tokens(v) }
    when Array then node.map { |v| resolve_tokens(v) }
    when String then replace_contact_tokens(node)
    else node
    end
  end

  def replace_contact_tokens(str)
    str.gsub(/\{contact\.([a-z_]+)(?:\.([^}]+))?\}/) do
      contact_token_value(Regexp.last_match(1), Regexp.last_match(2))
    end
  end

  def contact_token_value(field, key)
    case field
    when 'name' then @contact.name.to_s
    when 'phone', 'phone_number' then @contact.phone_number.to_s
    when 'email' then @contact.email.to_s
    when 'attr', 'custom' then (@contact.custom_attributes || {})[key].to_s
    else ''
    end
  end

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

  # A campaign can carry a SEQUENCE of messages (message['messages']). Each is
  # sent in order. Legacy single-message campaigns (flat text/attachment) still
  # work via the fallback.
  def send_message(conversation)
    broadcast_messages.each { |m| build_one(conversation, m) }
  end

  def broadcast_messages
    msg = @broadcast.message || {}
    list = msg['messages']
    list.is_a?(Array) && list.any? ? list : [msg]
  end

  def build_one(conversation, message_part)
    attachment = message_part['attachment']
    content = attachment.present? ? message_part['caption'] : message_part['text']
    return if content.blank? && attachment.blank?

    params = { content: content, message_type: 'outgoing' }
    params[:attachments] = [attachment] if attachment.present?
    Messages::MessageBuilder.new(nil, conversation, params).perform
  end

  def mark_failed(message)
    @recipient.update!(status: :failed, error: message)
  end
end
