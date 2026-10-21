# Números das listas: por lista (detalhe), em lote (cartões da página) e da
# conta inteira (cards do topo). "Disparáveis" = ativos com telefone e com
# consentimento; quem nunca falou com o salão aparece à parte, porque o
# disparo só os alcança com confirmação.
class ContactLists::Summary
  def self.counts_for(list_ids)
    rows = ContactListMember.where(contact_list_id: list_ids).left_joins(:contact)
                            .group(:contact_list_id)
                            .pluck(:contact_list_id, Arel.sql(left_sql), Arel.sql(no_phone_sql))
    rows.to_h { |id, left, no_phone| [id, { left: left, no_phone: no_phone }] }
  end

  def self.for_list(list)
    new(list.account, ContactListMember.where(contact_list_id: list.id)).to_h
  end

  def self.for_account(account)
    lists = account.contact_lists
    new(account, ContactListMember.where(contact_list_id: lists.select(:id)))
      .to_h.merge(lists: lists.count, group_lists: lists.where(source: 'group').count)
  end

  def self.left_sql
    "COUNT(*) FILTER (WHERE contact_list_members.status = #{ContactListMember.statuses[:left]})"
  end

  def self.no_phone_sql
    "COUNT(*) FILTER (WHERE contact_list_members.status = #{ContactListMember.statuses[:active]} " \
      "AND COALESCE(contacts.phone_number, '') = '')"
  end

  def initialize(account, members)
    @account = account
    @members = members
  end

  def to_h
    active = @members.status_active
    with_phone = active.joins(:contact).where.not(contacts: { phone_number: [nil, ''] }).distinct.pluck(:contact_id)
    cold = Contacts::BroadcastConsent.unconsented_ids(@account, with_phone).length
    {
      active: active.count, contacts: active.where.not(contact_id: nil).distinct.count(:contact_id),
      left: @members.status_left.count, no_phone: active.left_joins(:contact).where(contacts: { phone_number: [nil, ''] }).count,
      unconsented: cold, sendable: with_phone.length - cold
    }
  end
end
