# Ponto único para pôr e tirar contatos de uma lista. Usado pelas telas
# (adicionar à mão, CSV, filtro, mesclar) e por quem mais precisar — o bloco
# "adicionar/remover de lista" do Chatflow chama exatamente isto:
#
#   ContactLists::MemberService.new(list).add([contact.id])
#   ContactLists::MemberService.new(list).remove([contact.id])
#
# Só aceita contatos da conta da lista. Quem tinha saído (status left) volta a
# ficar ativo ao ser adicionado de novo. Devolve quantos mudaram.
class ContactLists::MemberService
  def initialize(list)
    @list = list
  end

  def add(contact_ids, joined_at: Time.current)
    ids = @list.account.contacts.where(id: Array(contact_ids).map(&:to_i)).pluck(:id)
    return 0 if ids.empty?

    existing = @list.members.where(contact_id: ids)
    back = { status: :active, left_at: nil, joined_at: joined_at, updated_at: Time.current }
    reactivated = existing.status_left.update_all(back) # rubocop:disable Rails/SkipsModelValidations
    fresh = ids - existing.pluck(:contact_id)
    insert(fresh, joined_at)
    @list.recount!
    reactivated + fresh.length
  end

  def remove(contact_ids)
    removed = @list.members.where(contact_id: Array(contact_ids).map(&:to_i)).delete_all
    @list.recount!
    removed
  end

  # Tira membros pelo id da linha (inclui os "sem telefone", que não têm contato).
  def remove_members(member_ids)
    removed = @list.members.where(id: Array(member_ids).map(&:to_i)).delete_all
    @list.recount!
    removed
  end

  private

  def insert(contact_ids, joined_at)
    return if contact_ids.empty?

    now = Time.current
    rows = contact_ids.map { |id| { contact_list_id: @list.id, contact_id: id, status: 0, joined_at: joined_at, created_at: now, updated_at: now } }
    unique = :index_contact_list_members_on_list_and_contact
    ContactListMember.insert_all(rows, unique_by: unique) # rubocop:disable Rails/SkipsModelValidations
  end
end
