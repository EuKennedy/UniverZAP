# Ponte entre o Chatflow e as listas de distribuição (branch
# univerzap/listas-distribuicao). Este é o ÚNICO lugar do Chatflow que conhece
# esse modelo: enquanto ele não estiver na base, `available?` é falso, a etapa
# "Lista" é pulada (o fluxo segue) e o gatilho "entrou na lista" nunca dispara.
#
# Contrato combinado com a sessão de listas:
#   ContactList (account.contact_lists, `name`)
#   ContactLists::MemberService.new(list).add(contact_ids)    → quantos entraram (reativa quem saiu)
#   ContactLists::MemberService.new(list).remove(contact_ids) → quantos saíram
# O MemberService grava com insert_all/update_all, então não há callback nem
# evento ao adicionar: quem chama o gatilho é esta ponte (quando a etapa
# adiciona) e, do lado das listas, quem adicionar por tela/importação/extração
# deve chamar `Chatflow::TriggerDispatcher.list_entered(list, contact)`.
module Chatflow::ListBridge
  module_function

  def available?
    defined?(::ContactList).present? && defined?(::ContactLists::MemberService).present?
  end

  def lists_for(account)
    return [] unless available?

    ::ContactList.where(account_id: account.id).order(:name).map { |list| { id: list.id, name: list.name } }
  end

  def find(account, list_id)
    return unless available?

    ::ContactList.find_by(account_id: account.id, id: list_id)
  end

  # Devolve true quando mexeu na lista. Entrar pela etapa também conta como
  # "entrou na lista" — mas o dispatcher ignora a conversa que já está num fluxo.
  def apply(account, contact, list_id, action)
    list = find(account, list_id)
    return false if list.blank? || contact.blank?

    service = ::ContactLists::MemberService.new(list)
    return service.remove([contact.id]).to_i.positive? if action.to_s == 'remove'

    added = service.add([contact.id]).to_i.positive?
    Chatflow::TriggerDispatcher.list_entered(list, contact) if added
    added
  end
end
