# Extração / atualização de participantes de grupo em segundo plano: um grupo
# grande com muitos @lid faz uma chamada à WAHA por LID. A tela acompanha pelo
# status da lista (importing → ready | failed).
class ContactLists::GroupExtractionJob < ApplicationJob
  queue_as :low

  def perform(list_id)
    list = ContactList.find_by(id: list_id)
    return unless list&.group?

    ContactLists::GroupExtractionService.new(list).perform
  rescue Whatsapp::WahaSessionService::WahaError, Whatsapp::WahaInboxResolver::NotWahaInboxError, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[ContactLists] extraction failed list=#{list_id}: #{e.message}")
    list&.update!(status: 'failed', last_error: e.message.truncate(250))
  end
end
