# A WAHA baixa a mídia por URL, então o arquivo precisa estar num endereço
# alcançável a partir do container dela, e não do navegador do usuário.
# Reaproveita o blob do ActiveStorage com uma URL assinada mais longa que o
# padrão: um vídeo de status leva mais tempo para baixar que uma foto.
module Whatsapp::WahaMediaUrl
  TTL = 15.minutes

  def self.for(blob)
    ActiveStorage::Current.url_options = Rails.application.routes.default_url_options if ActiveStorage::Current.url_options.blank?
    blob.url(expires_in: TTL)
  end
end
