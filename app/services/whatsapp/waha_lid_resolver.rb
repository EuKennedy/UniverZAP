# Troca o LID (o id anônimo que o WhatsApp usa em leads de anúncio e em
# comunidades) pelo número de telefone, perguntando à sessão WAHA da caixa.
#
# Um contato chega só com LID por dois caminhos: o app Chatwoot da WAHA, que
# o cria pela API pública com identifier "…@lid" e nome igual ao LID, e o
# webhook nativo (Webhooks::WahaEventsJob). Nos dois o contato nasce sem
# telefone, e a resposta pronta com {{contact.name}} sai como "159…@lid".
#
# Quando a WAHA conhece o número, grava phone_number e waha_whatsapp_jid; se
# outro contato da conta já tem esse número, mescla neste em vez de duplicar.
# Sem número, só garante que o nome não seja o LID cru.
class Whatsapp::WahaLidResolver
  LID_SUFFIX = '@lid'.freeze

  def self.pending?(contact)
    contact.phone_number.blank? && contact.identifier.to_s.end_with?(LID_SUFFIX)
  end

  # Vale enfileirar de novo: contato de LID sem telefone que acabou de nascer
  # ou que a ponte acabou de mexer (identifier, nome, atributos). O último
  # visto muda a cada mensagem e não conta, senão seriam duas chamadas à WAHA
  # por mensagem recebida.
  def self.worth_retrying?(contact)
    pending?(contact) && (contact.previously_new_record? || contact.saved_changes.keys.intersect?(%w[identifier name custom_attributes]))
  end

  def initialize(contact)
    @contact = contact
    @lid = contact.identifier.to_s
  end

  # Devolve o que aconteceu, para o rake contar: :resolved, :merged,
  # :unresolved ou :skipped (não é um contato de LID numa caixa WAHA).
  def perform
    return :skipped unless self.class.pending?(@contact) && service

    phone = phone_number
    return rename_without_phone unless phone

    existing = @contact.account.contacts.where.not(id: @contact.id).find_by(phone_number: phone)
    existing ? merge_into(existing, phone) : attach_phone(phone)
  end

  private

  def service
    @service ||= begin
      account = @contact.account
      resolver = Whatsapp::WahaInboxResolver.new(account)
      inbox = @contact.inboxes.detect { |candidate| resolver.session_name_for(candidate).present? }
      resolver.resolve!(inbox.id).last if inbox
    end
  end

  # WAHA responde {"lid": "123@lid", "pn": "5511999@c.us"}; pn vem null quando
  # a sessão ainda não viu o número por trás do LID.
  def phone_number
    pn = service.find_phone_by_lid(@lid).to_h['pn']
    return if pn.blank?

    @jid = pn
    "+#{pn.split('@').first}"
  end

  def attach_phone(phone)
    @contact.update!(phone_number: phone, name: resolved_name(phone),
                     custom_attributes: @contact.custom_attributes.merge('waha_whatsapp_jid' => @jid, 'waha_whatsapp_lid' => @lid))
    :resolved
  end

  # O contato que já tinha o número fica; conversas, mensagens e caixas do
  # contato de LID passam para ele e o LID vira um dos seus endereços, que é
  # o que o app da WAHA procura na próxima mensagem.
  def merge_into(existing, phone)
    lid_attributes = { 'waha_whatsapp_jid' => @jid, 'waha_whatsapp_lid' => @lid }
    base = ContactMergeAction.new(account: @contact.account, base_contact: existing, mergee_contact: @contact).perform
    base.update!(phone_number: phone, custom_attributes: lid_attributes.merge(base.custom_attributes))
    :merged
  end

  def rename_without_phone
    @contact.update!(name: push_name || I18n.t('contacts.whatsapp.no_phone_number')) if raw_name?
    :unresolved
  end

  def resolved_name(phone)
    return @contact.name unless raw_name?

    push_name || phone
  end

  # Nome que ninguém digitou: vazio, o próprio LID, só os dígitos dele ou o
  # rótulo de "sem número" de uma passagem anterior.
  def raw_name?
    name = @contact.name.to_s.strip.downcase
    name.blank? || name == @lid || name == @lid.delete_suffix(LID_SUFFIX) || name == I18n.t('contacts.whatsapp.no_phone_number').downcase
  end

  def push_name
    return @push_name if defined?(@push_name)

    fetched = service.fetch_contact(chat_id: @jid || @lid)
    fetched = fetched.first if fetched.is_a?(Array)
    @push_name = fetched.to_h.values_at('pushname', 'pushName', 'name').find(&:present?)
  end
end
