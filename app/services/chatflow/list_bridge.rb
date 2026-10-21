# Ponte entre o Chatflow e as listas de distribuição.
#
# O modelo de lista nasce em paralelo, na branch univerzap/listas-distribuicao.
# Este é o ÚNICO lugar do Chatflow que conhece esse modelo: enquanto ele não
# existir, `available?` é falso, a etapa "Lista" é pulada (o fluxo segue) e o
# gatilho "entrou na lista" nunca dispara. Na integração, se o modelo tiver
# outro nome ou outro jeito de adicionar contato, só este arquivo muda.
#
# Contrato esperado (ajustar aqui na integração):
#   ContactList                 — belongs_to :account; has_many :contacts (através dos membros)
#   account.contact_lists       — escopo da conta
#   list.add_contact(contact)   — opcional; senão `list.contacts << contact`
#   list.remove_contact(contact) — opcional; senão `list.contacts.delete(contact)`
# E, do lado das listas, chamar `Chatflow::TriggerDispatcher.list_entered(list, contact)`
# quando um contato entra (por tela, importação ou por esta etapa).
module Chatflow::ListBridge
  module_function

  def available?
    defined?(::ContactList).present? && ::ContactList < ApplicationRecord
  end

  def lists_for(account)
    return [] unless available?

    ::ContactList.where(account_id: account.id).order(:name).map { |list| { id: list.id, name: list.name } }
  end

  def find(account, list_id)
    return unless available?

    ::ContactList.find_by(account_id: account.id, id: list_id)
  end

  # Devolve true quando mexeu na lista. Adicionar pela etapa também conta como
  # "entrou na lista" — mas o dispatcher ignora conversas que já estão num fluxo.
  def apply(account, contact, list_id, action)
    list = find(account, list_id)
    return false if list.blank? || contact.blank?

    action.to_s == 'remove' ? remove(list, contact) : add(list, contact)
    true
  end

  def add(list, contact)
    return list.add_contact(contact) if list.respond_to?(:add_contact)
    return if list.contacts.exists?(contact.id)

    list.contacts << contact
    Chatflow::TriggerDispatcher.list_entered(list, contact)
  end

  def remove(list, contact)
    return list.remove_contact(contact) if list.respond_to?(:remove_contact)

    list.contacts.delete(contact)
  end
end
