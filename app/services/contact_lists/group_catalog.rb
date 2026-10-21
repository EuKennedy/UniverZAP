# Os grupos de WhatsApp que a conta pode extrair: conversas de grupo nas
# caixas ligadas a uma sessão WAHA, com a lista que já existe para cada um.
class ContactLists::GroupCatalog
  LIMIT = 200

  def initialize(account)
    @account = account
    @resolver = Whatsapp::WahaInboxResolver.new(account)
  end

  def to_a
    inboxes = @resolver.waha_inboxes.index_by(&:id)
    return [] if inboxes.empty?

    conversations = group_conversations(inboxes.keys)
    lists = @account.contact_lists.where(source: 'group', group_identifier: conversations.filter_map { |c| c.contact&.identifier })
                    .index_by { |list| [list.inbox_id, list.group_identifier] }
    conversations.map { |conversation| row(conversation, inboxes[conversation.inbox_id], lists) }
  end

  # A lista do grupo desta conversa: a que já existe nesta caixa ou uma nova.
  def list_for!(conversation)
    if @resolver.session_name_for(conversation.inbox).blank?
      raise Whatsapp::WahaInboxResolver::NotWahaInboxError,
            I18n.t('inbox.whatsapp.waha.not_a_waha_inbox')
    end

    identifier = conversation.contact.identifier
    @account.contact_lists.from_group(identifier).find_by(inbox_id: conversation.inbox_id) ||
      @account.contact_lists.create!(name: conversation.contact.name.presence || identifier, source: 'group', inbox_id: conversation.inbox_id,
                                     group_identifier: identifier,
                                     metadata: { 'group_name' => conversation.contact.name, 'conversation_id' => conversation.display_id })
  end

  private

  def group_conversations(inbox_ids)
    @account.conversations.groups.where(inbox_id: inbox_ids).includes(:contact).order(last_activity_at: :desc).limit(LIMIT)
            .to_a.uniq { |conversation| [conversation.inbox_id, conversation.contact_id] }
  end

  def row(conversation, inbox, lists)
    list = lists[[conversation.inbox_id, conversation.contact&.identifier]]
    {
      conversation_id: conversation.id, display_id: conversation.display_id, name: conversation.contact&.name,
      thumbnail: conversation.contact&.avatar_url, inbox_id: inbox.id, inbox_name: inbox.name,
      last_activity_at: conversation.last_activity_at&.to_i,
      list_id: list&.id, list_members_count: list&.members_count, list_refreshed_at: list&.refreshed_at&.to_i
    }
  end
end
