# Junta várias listas da conta numa lista nova (as originais ficam como
# estão). Só os membros ativos com contato entram; cada contato uma vez só, e
# no fim a lista nova passa pela deduplicação por telefone.
class ContactLists::MergeService
  def initialize(account:, list_ids:, name:, description: nil)
    @account = account
    @lists = account.contact_lists.where(id: Array(list_ids).map(&:to_i))
    @name = name
    @description = description
  end

  def perform
    raise ArgumentError, I18n.t('contact_lists.errors.merge_needs_two') if @lists.size < 2

    merged = ContactList.transaction do
      list = @account.contact_lists.create!(name: @name.presence || default_name, description: @description, source: 'manual',
                                            metadata: { 'merged_from' => @lists.map(&:id) })
      ids = ContactListMember.where(contact_list_id: @lists.select(:id)).status_active.where.not(contact_id: nil).distinct.pluck(:contact_id)
      ContactLists::MemberService.new(list).add(ids)
      ContactLists::DeduplicateService.new(list).perform
      list.reload
    end
    ContactLists::EntryNotifier.call(merged, merged.members.status_active.pluck(:contact_id))
    merged
  end

  private

  def default_name
    @lists.map(&:name).join(' + ').truncate(120)
  end
end
