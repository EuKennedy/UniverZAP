# Roda fora do request porque resolver o LID é uma chamada HTTP à WAHA, e o
# contato nasce tanto no webhook nativo quanto na API pública usada pelo app
# Chatwoot da WAHA. Enfileirado por Contact sempre que um contato com
# identifier "…@lid" é salvo sem telefone.
class Whatsapp::WahaResolveLidJob < ApplicationJob
  queue_as :low

  def perform(contact_id)
    contact = Contact.find_by(id: contact_id)
    return unless contact

    Whatsapp::WahaLidResolver.new(contact).perform
  end
end
