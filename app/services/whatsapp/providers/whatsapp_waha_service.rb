class Whatsapp::Providers::WhatsappWahaService < Whatsapp::Providers::BaseService
  def send_message(phone_number, message)
    @message = message
    chat_id = chat_id_for(phone_number)
    if message.attachments.present?
      send_attachment_message(chat_id, message)
    else
      send_text_message(chat_id, message)
    end
  end

  def send_template(phone_number, _template_info, message)
    # WAHA non-official providers don't support real WhatsApp templates,
    # so we fall back to plain text using the resolved outgoing content.
    send_text_message(chat_id_for(phone_number), message)
  end

  def sync_templates
    whatsapp_channel.mark_message_templates_updated
    whatsapp_channel.update(message_templates: [])
  end

  def validate_provider_config?
    session = session_service.session
    session.present? && %w[STARTING WORKING SCAN_QR_CODE FAILED STOPPED].include?(session['status'])
  rescue Whatsapp::WahaSessionService::WahaError
    false
  end

  def api_headers
    {
      'Content-Type' => 'application/json',
      'X-Api-Key' => whatsapp_channel.provider_config['api_key'].presence || ENV.fetch('WAHA_API_KEY', nil)
    }
  end

  def media_url(media_id)
    "#{base_url}/api/files/#{media_id}"
  end

  def session_service
    @session_service ||= Whatsapp::WahaSessionService.new(
      session_name: whatsapp_channel.provider_config['session_name'],
      base_url: whatsapp_channel.provider_config['base_url'],
      api_key: whatsapp_channel.provider_config['api_key']
    )
  end

  private

  def base_url
    (whatsapp_channel.provider_config['base_url'].presence || ENV.fetch('WAHA_BASE_URL', '')).chomp('/')
  end

  def chat_id_for(phone_number)
    digits = phone_number.to_s.gsub(/\D/, '')
    digits.include?('@') ? phone_number : "#{digits}@c.us"
  end

  def send_text_message(chat_id, message)
    response = session_service.send_text(
      chat_id: chat_id,
      text: message.outgoing_content,
      # The Cloud provider has always forwarded this (as `context.message_id`);
      # WAHA dropped it, so a quoted reply arrived here as a plain message.
      reply_to: message.content_attributes[:in_reply_to_external_id]
    )
    extract_message_id(response, message)
  rescue Whatsapp::WahaSessionService::WahaError => e
    handle_waha_error(e, message)
  end

  def send_attachment_message(chat_id, message)
    attachment = message.attachments.first
    type = attachment_type(attachment)
    response = session_service.send_media(
      chat_id: chat_id,
      type: type,
      url: attachment.download_url,
      caption: %w[audio sticker].include?(type) ? nil : message.outgoing_content,
      filename: type == 'document' ? attachment.file.filename.to_s : nil
    )
    extract_message_id(response, message)
  rescue Whatsapp::WahaSessionService::WahaError => e
    handle_waha_error(e, message)
  end

  def attachment_type(attachment)
    return attachment.file_type if %w[image audio video].include?(attachment.file_type)

    'document'
  end

  def extract_message_id(response, _message)
    return nil if response.blank?

    response.dig('id', '_serialized') || response['id'] || response.dig('data', 'id') || nil
  end

  def handle_waha_error(error, message)
    Rails.logger.error("[WAHA] send failed: #{error.message}")
    return if message.blank?

    message.update!(status: :failed, external_error: error.message.truncate(500))
    nil
  end
end
