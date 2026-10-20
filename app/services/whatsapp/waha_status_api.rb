# Status (stories) do WhatsApp pela WAHA. Endpoints do WAHA Core, suportados
# nos quatro engines (WEBJS, WPP, NOWEB, GOWS).
# Docs: https://waha.devlike.pro/docs/how-to/status/
# Campos conferidos no DTO da WAHA (src/structures/status.dto.ts): texto aceita
# `font` e `backgroundColor`; imagem e vídeo aceitam `caption`.
#
# Nenhum método manda `contacts`: sem esse campo a WAHA publica para todos os
# contatos, que é o comportamento que a tela promete. O engine WEBJS nem aceita
# `contacts`, então omitir é também o único jeito de valer para todos.
#
# Mora num módulo à parte pelo mesmo motivo de WahaProfileApi: reaproveitar o
# `request` de WahaSessionService sem estourar o ClassLength daquela classe.
module Whatsapp::WahaStatusApi
  def send_status_text(text:, background_color: nil, font: nil)
    body = { text: text }
    body[:backgroundColor] = background_color if background_color.present?
    body[:font] = font unless font.nil?
    request(:post, "/api/#{@session_name}/status/text", body: body)
  end

  def send_status_image(url:, caption: nil, mimetype: 'image/jpeg')
    body = { file: { mimetype: mimetype, url: url } }
    body[:caption] = caption if caption.present?
    request(:post, "/api/#{@session_name}/status/image", body: body)
  end

  # `convert` deixa a WAHA reempacotar o arquivo: o WhatsApp só aceita status em
  # mp4/libx264 e o vídeo que o usuário sobe do celular raramente já está assim.
  def send_status_video(url:, mimetype: 'video/mp4', caption: nil, background_color: nil, convert: true)
    body = { file: { mimetype: mimetype, url: url }, convert: convert }
    body[:caption] = caption if caption.present?
    body[:backgroundColor] = background_color if background_color.present?
    request(:post, "/api/#{@session_name}/status/video", body: body)
  end
end
