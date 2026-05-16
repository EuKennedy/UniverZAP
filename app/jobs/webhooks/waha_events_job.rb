class Webhooks::WahaEventsJob < ApplicationJob
  queue_as :default

  def perform(event)
    event = event.with_indifferent_access
    session_name = event[:session]
    return if session_name.blank?

    channel = Channel::Whatsapp.where(provider: 'waha')
                               .where("provider_config->>'session_name' = ?", session_name)
                               .first
    return unless channel

    case event[:event]
    when 'message', 'message.any'
      handle_message(channel, event)
    when 'message.ack'
      handle_ack(channel, event)
    when 'session.status'
      handle_session_status(channel, event)
    end
  end

  private

  def handle_message(channel, event)
    payload = event[:payload] || {}
    return if payload.blank?

    # message.any duplicates message; skip the duplicate when fromMe is false.
    return if event[:event] == 'message.any' && payload[:fromMe] == false

    inbox = channel.inbox
    normalized = normalize_to_cloud_api(payload)
    Whatsapp::IncomingMessageWahaService.new(
      inbox: inbox,
      params: normalized,
      outgoing_echo: payload[:fromMe] == true
    ).perform
  rescue StandardError => e
    Rails.logger.error("[WAHA events] message handling failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
  end

  def handle_ack(channel, event)
    payload = event[:payload] || {}
    message = find_ack_message(channel, payload)
    return unless message

    status = ack_status(payload[:ack] || payload[:ackName])
    message.update(status: status) if status
  rescue StandardError => e
    Rails.logger.error("[WAHA events] ack handling failed: #{e.message}")
  end

  def find_ack_message(channel, payload)
    source_id = payload[:id].is_a?(Hash) ? payload.dig(:id, :_serialized) : payload[:id]
    return nil if source_id.blank?

    channel.inbox.messages.find_by(source_id: source_id.to_s)
  end

  def handle_session_status(channel, event)
    status = event.dig(:payload, :status)
    return if status.blank?

    case status
    when 'FAILED', 'STOPPED'
      channel.prompt_reauthorization!
    when 'WORKING'
      channel.reauthorized!
    end
  rescue StandardError => e
    Rails.logger.error("[WAHA events] session status failed: #{e.message}")
  end

  def ack_status(ack)
    case ack.to_s
    when '1', 'SERVER', 'sent' then 'sent'
    when '2', 'DEVICE', 'delivered' then 'delivered'
    when '3', '4', 'READ', 'PLAYED', 'read' then 'read'
    end
  end

  # Reshape WAHA event into the Meta cloud-api format expected by
  # Whatsapp::IncomingMessageBaseService.
  def normalize_to_cloud_api(payload)
    from_jid = payload[:fromMe] ? payload[:to] : payload[:from]
    phone_digits = from_jid.to_s.split('@').first
    {
      'entry' => [
        {
          'changes' => [
            {
              'value' => {
                'messaging_product' => 'whatsapp',
                'metadata' => { 'display_phone_number' => phone_digits, 'phone_number_id' => phone_digits },
                'contacts' => [build_contact_hash(payload, phone_digits)],
                'messages' => [build_message_hash(payload, phone_digits)]
              }
            }
          ]
        }
      ]
    }
  end

  def build_contact_hash(payload, phone_digits)
    name = payload.dig(:_data, :notifyName) ||
           payload.dig(:contact, :pushName) ||
           payload.dig(:contact, :name)
    { 'profile' => { 'name' => name }, 'wa_id' => phone_digits }
  end

  def build_message_hash(payload, phone_digits)
    source_id = payload[:id].is_a?(Hash) ? payload.dig(:id, :_serialized) : payload[:id]
    base = {
      'id' => source_id.to_s,
      'from' => phone_digits,
      'to' => payload[:to].to_s.split('@').first,
      'timestamp' => payload[:timestamp].to_i.to_s
    }
    base.merge(message_content_payload(payload))
  end

  def message_content_payload(payload)
    if payload[:hasMedia] && payload[:media].present?
      media_type = media_type_for(payload.dig(:media, :mimetype) || payload[:mimetype])
      {
        'type' => media_type,
        media_type => {
          'id' => payload.dig(:media, :id) || payload[:id].to_s,
          'mime_type' => payload.dig(:media, :mimetype),
          'caption' => payload[:body],
          'link' => payload.dig(:media, :url),
          'filename' => payload.dig(:media, :filename)
        }.compact
      }
    else
      { 'type' => 'text', 'text' => { 'body' => payload[:body].to_s } }
    end
  end

  def media_type_for(mime)
    return 'document' if mime.blank?

    case mime.split('/').first
    when 'image' then 'image'
    when 'video' then 'video'
    when 'audio' then 'audio'
    else 'document'
    end
  end
end
