class Whatsapp::IncomingMessageWahaService < Whatsapp::IncomingMessageBaseService
  private

  # The WAHA controller normalizes payload to look similar to the cloud-api shape
  # so the base service can reuse most of its logic. See Webhooks::WahaController.
  def processed_params
    @processed_params ||= params[:entry].try(:first).try(:[], 'changes').try(:first).try(:[], 'value')
  end

  # Mensagem vinda de um LID (lead de anúncio sem JID de telefone): o contato
  # nasce pelo identifier, sem telefone, com o pushName ou o rótulo "sem
  # número" — nunca os dígitos do LID como se fossem um telefone. O número é
  # buscado depois pelo Whatsapp::WahaResolveLidJob, que o Contact enfileira.
  def set_contact
    lid = @processed_params.dig(:contacts, 0, :lid)
    return super if lid.blank?

    name = @processed_params.dig(:contacts, 0, :profile, :name).presence || I18n.t('contacts.whatsapp.no_phone_number')
    @contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: lid,
      inbox: inbox,
      contact_attributes: { name: name, identifier: lid, custom_attributes: { 'waha_whatsapp_lid' => lid } }
    ).perform
    @contact = @contact_inbox.contact
  end

  def download_attachment_file(attachment_payload)
    media_url = attachment_payload[:link] || attachment_payload[:url] ||
                inbox.channel.provider_service.media_url(attachment_payload[:id])
    headers = inbox.channel.api_headers
    Down.download(media_url, headers: headers, max_size: 50 * 1024 * 1024)
  rescue StandardError => e
    Rails.logger.error("[WAHA] media download failed: #{e.message}")
    nil
  end
end
