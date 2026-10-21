# A mesma pessoa pode estar na base duas vezes — o mesmo celular gravado com e
# sem o nono dígito, ou com máscaras diferentes. Na lista, ela fica uma vez
# só (o contato mais antigo), para não receber o disparo em dobro. Membros
# "sem telefone" repetidos pelo mesmo nome não são tocados: sem número não dá
# para ter certeza de que é a mesma pessoa. Os contatos em si não são mesclados.
class ContactLists::DeduplicateService
  def initialize(list)
    @list = list
  end

  def perform
    duplicates = @list.members.status_active.joins(:contact).where.not(contacts: { phone_number: [nil, ''] })
                      .pluck(:id, :contact_id, 'contacts.phone_number')
                      .group_by { |_id, _contact_id, phone| canonical(phone) }
                      .values.select { |rows| rows.length > 1 }
                      .flat_map { |rows| rows.sort_by { |_id, contact_id, _phone| contact_id }.drop(1).map(&:first) }
    removed = @list.members.where(id: duplicates).delete_all
    @list.recount!
    removed
  end

  private

  def canonical(phone)
    Broadcasts::PhoneNumber.normalize(phone) || phone
  end
end
