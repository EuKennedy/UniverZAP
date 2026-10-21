# "Entrou na lista": avisa o Chatflow (gatilho list_entered) quando alguém
# entra numa lista pela tela, CSV, filtro, mesclagem ou extração de grupo.
# O bloco do próprio Chatflow chama MemberService#add sem `notify` e dispara
# o gatilho por conta própria — assim ninguém recebe o gatilho duas vezes.
#
# Quem nunca falou com o salão (Contacts::BroadcastConsent) não dispara
# fluxo: mensagem automática para contato frio é o mesmo risco de bloqueio
# e de LGPD que o disparo só aceita com confirmação explícita.
class ContactLists::EntryNotifier
  def self.call(list, contact_ids)
    ids = Array(contact_ids).compact.uniq
    return if ids.empty? || !defined?(Chatflow::TriggerDispatcher)

    ids -= Contacts::BroadcastConsent.unconsented_ids(list.account, ids)
    list.account.contacts.where(id: ids).find_each { |contact| Chatflow::TriggerDispatcher.list_entered(list, contact) }
  end
end
