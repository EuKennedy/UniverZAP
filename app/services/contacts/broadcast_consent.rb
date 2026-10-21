# Consentimento para disparo (decisão do dono, número não oficial + LGPD).
#
# Contato que nasce pela extração de participantes de grupo (ou por um CSV
# marcado como "nunca falaram com o salão") recebe o atributo
# `consentimento_disparo = false`. Ele só entra num disparo quando:
#   - já conversou com a conta (mandou mensagem numa conversa direta, que não
#     é de grupo) — isso vale como consentimento, sem precisar mexer no
#     atributo; ou
#   - alguém marcou o atributo como verdadeiro na ficha; ou
#   - o disparo tem a confirmação "estes contatos nunca falaram com o salão"
#     gravada (Broadcast#cold_contacts_confirmed?).
# Contato sem o atributo (a base inteira de antes) conta como consentido.
class Contacts::BroadcastConsent
  ATTRIBUTE = 'consentimento_disparo'.freeze

  def self.mark_unconsented!(contact)
    contact.update!(custom_attributes: (contact.custom_attributes || {}).merge(ATTRIBUTE => false))
  end

  # Entre `ids`, quem nunca consentiu: atributo falso e nenhuma mensagem
  # recebida dela numa conversa direta com a conta.
  def self.unconsented_ids(account, ids)
    ids = Array(ids)
    return [] if ids.empty?

    flagged = account.contacts.where(id: ids).where("contacts.custom_attributes->>'#{ATTRIBUTE}' = 'false'").pluck(:id)
    return [] if flagged.empty?

    flagged - talked_ids(account, flagged)
  end

  def self.talked_ids(account, ids)
    Message.unscope(:order).where(account_id: account.id, message_type: :incoming)
           .joins(:conversation).where(conversations: { contact_id: ids, is_group: false })
           .distinct.pluck('conversations.contact_id')
  end

  # Aparece na ficha como uma caixa de seleção, para o salão poder registrar
  # um consentimento obtido fora do WhatsApp.
  def self.ensure_definition!(account)
    account.custom_attribute_definitions.find_or_create_by!(attribute_key: ATTRIBUTE, attribute_model: :contact_attribute) do |definition|
      definition.attribute_display_name = I18n.t('contact_lists.consent.display_name')
      definition.attribute_description = I18n.t('contact_lists.consent.description')
      definition.attribute_display_type = :checkbox
    end
  end
end
