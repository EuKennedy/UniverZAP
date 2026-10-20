# A WahaError carrega método, path e o corpo cru da resposta. Para a tela
# interessa o que a WAHA respondeu, então extraímos a mensagem do JSON e só
# caímos no texto inteiro quando não há nada estruturado para mostrar.
module Whatsapp::WahaErrorMessage
  def self.humanize(message)
    message = message.to_s
    payload = message[/\{.*\}/m]
    parsed = payload.present? ? JSON.parse(payload) : nil
    return message unless parsed.is_a?(Hash)

    (parsed['message'] || parsed['error']).to_s.presence || message
  rescue JSON::ParserError
    message
  end
end
