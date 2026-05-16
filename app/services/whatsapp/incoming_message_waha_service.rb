class Whatsapp::IncomingMessageWahaService < Whatsapp::IncomingMessageBaseService
  private

  # The WAHA controller normalizes payload to look similar to the cloud-api shape
  # so the base service can reuse most of its logic. See Webhooks::WahaController.
  def processed_params
    @processed_params ||= params[:entry].try(:first).try(:[], 'changes').try(:first).try(:[], 'value')
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
