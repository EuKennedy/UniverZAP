# Sends one broadcast recipient. WAHA mode goes through Messages::MessageBuilder
# — exactly like Chatflow::NodeRunnerService — so it renders in the Chatwoot
# timeline AND dispatches to WhatsApp. Official mode ships an approved template
# through the Meta Cloud API and then records what left.
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

  # Official (Meta Cloud API): send an approved template, then persist it so the
  # thread shows what the customer received.
  def send_official
    external_id = deliver_template
    # `send_template` answers with the provider's message id, or nil when Meta
    # refused — a paused template, a number not on WhatsApp, the tier limit.
    # Trusting the call instead of its answer is what reported whole broadcasts
    # as sent while nothing had left.
    return mark_failed('provider refused the template') if external_id.blank?

    conversation = find_or_create_conversation
    record_official_message(conversation, external_id)
    @recipient.update!(status: :sent, sent_at: Time.current, conversation_id: conversation.display_id)
  end

  def deliver_template
    channel = @inbox.channel
    raise 'official mode needs a WhatsApp Cloud inbox' unless channel.respond_to?(:send_template)
    raise 'missing template config' if official_template_params.blank?

    name, namespace, lang_code, parameters = Whatsapp::TemplateProcessorService.new(
      channel: channel, template_params: official_template_params, message: nil
    ).call
    # The processor echoes the requested name back whatever happens, so `name`
    # proves nothing. `parameters` is nil only when the template is absent from
    # the channel cache or is not approved — that is the real existence check.
    raise "template '#{name}' is not approved on this inbox" if parameters.nil?

    channel.send_template(@contact.phone_number,
                          { name: name, namespace: namespace, lang_code: lang_code, parameters: parameters }, nil)
  end

  # The template already left through the Cloud API, so it is stored carrying
  # the provider id: Base::SendOnChannelService skips any message that has a
  # source_id, which is what keeps this from going out a second time.
  def record_official_message(conversation, external_id)
    ::Message.create!(
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      conversation_id: conversation.id,
      message_type: :outgoing,
      content: template_preview,
      source_id: external_id,
      additional_attributes: { 'template_params' => official_template_params }
    )
  end

  # The body the customer actually received, so an agent opening the thread
  # later reads the template instead of an empty conversation.
  def template_preview
    template = @inbox.channel.message_templates.to_a.find { |t| t['name'] == official_template_params['name'] }
    body = template && Array(template['components']).find { |c| c['type'] == 'BODY' }
    return official_template_params['name'].to_s if body.blank? || body['text'].blank?

    fill_in(body['text'])
  end

  def fill_in(text)
    values = official_template_params.dig('processed_params', 'body') || {}
    values.each_with_index.reduce(text) do |acc, ((key, value), index)|
      acc.gsub("{{#{key}}}", value.to_s).gsub("{{#{index + 1}}}", value.to_s)
    end
  end

  def official_template_params
    @official_template_params ||= Broadcasts::ContactTokenResolver.new(@contact).resolve(@broadcast.message['template'])
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
