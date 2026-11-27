# Leva para as sessões e apps WAHA que já existem o que só vale para os criados
# daqui para a frente (`lib/tasks/waha.rake`). Rodar mais de uma vez não muda
# nada além da primeira.
class Whatsapp::WahaRollout
  INBOX_CONTACT = 'whatsapp.integration'.freeze
  DONATIONS = "content ILIKE '%Apoie o WAHA%' OR content ILIKE '%Support WAHA%' OR content ILIKE '%WAHA Core%'".freeze

  def initialize(out: $stdout)
    @out = out
  end

  # Nosso webhook com as 10 tentativas exponenciais e, com WAHA_WEBHOOK_HMAC_KEY,
  # a assinatura. Só nas sessões que já entregam para nós; as outras ficam como estão.
  def sync_webhooks!
    url = Whatsapp::WahaSessionService.webhook_url
    raise ArgumentError, 'FRONTEND_URL is not set' if url.start_with?('/')

    session_services.each { |service| sync_webhook(service, url) }
  end

  # O contato de avisos do app de Chatwoot da WAHA ("Integração WhatsApp", com o
  # logo da WAHA) vira UniverZAP nos apps e nos contatos já criados. As mensagens
  # "Apoie o WAHA" (a WAHA parou de mandar na 2026.9.1) só são apagadas quando pedido.
  def rebrand!(delete_donations: false)
    installed_channels.each { |channel| rebrand_app(channel) }
    rename_inbox_contacts
    donations = Message.where(sender_type: 'Contact', sender_id: inbox_contacts.select(:id)).where(DONATIONS)
    return @out.puts("mensagens de doação encontradas: #{donations.count} (APAGAR_DOACOES=1 para apagar)") unless delete_donations

    @out.puts("mensagens de doação apagadas: #{donations.destroy_all.size}")
  end

  private

  def sync_webhook(service, url)
    return unless service.current_webhooks.any? { |hook| hook['url'] == url }

    service.update_webhook(webhook_url: url)
    @out.puts("ok     #{service.session_name}")
  rescue Whatsapp::WahaSessionService::WahaError => e
    @out.puts("falhou #{service.session_name}: #{e.message}")
  end

  def rebrand_app(channel)
    Whatsapp::WahaSessionService.new(session_name: channel.additional_attributes['session_name']).rebrand_chatwoot_apps!
  rescue Whatsapp::WahaSessionService::WahaError => e
    @out.puts("app falhou #{channel.additional_attributes['session_name']}: #{e.message}")
  end

  def rename_inbox_contacts
    brand = Whatsapp::WahaSessionService.new.brand_templates
    inbox_contacts.find_each do |contact|
      contact.update!(name: brand['app.inbox.contact.name'])
      Avatar::AvatarFromUrlJob.perform_later(contact, brand['app.inbox.contact.avatar.url'])
    end
    @out.puts("contatos renomeados: #{inbox_contacts.count}")
  end

  def inbox_contacts
    Contact.where(identifier: INBOX_CONTACT)
  end

  def session_services
    native = Channel::Whatsapp.where(provider: 'waha').map { |channel| channel.provider_service.session_service }
    native + installed_channels.map { |channel| Whatsapp::WahaSessionService.new(session_name: channel.additional_attributes['session_name']) }
  end

  def installed_channels
    Channel::Api.where("additional_attributes->>'source' = 'waha'")
  end
end
