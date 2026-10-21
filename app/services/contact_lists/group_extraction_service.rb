# Extrai (ou atualiza) os participantes de um grupo do WhatsApp para uma
# lista de distribuição, pela sessão WAHA da caixa do grupo. Só LÊ da WAHA;
# nenhuma mensagem sai daqui.
#
# Para cada participante:
#   - casa com um contato da conta pelo telefone E.164 (com e sem o nono
#     dígito) ou pelo LID já conhecido; só cria contato quando não acha;
#   - quem vem só com @lid tem o número perguntado à WAHA (`/lids/{lid}`, o
#     mesmo do Whatsapp::WahaLidResolver); sem resposta, entra na lista como
#     "sem telefone" (membro sem contato), fora de qualquer disparo;
#   - contato criado aqui nasce com consentimento_disparo = false
#     (Contacts::BroadcastConsent);
#   - recebe a etiqueta do grupo ("grupo-<nome>").
# Numa atualização, quem não está mais no grupo vira `left` e quem chegou
# ganha `joined_at` desta passada; o resumo fica em metadata['last_run'].
class ContactLists::GroupExtractionService
  PHONE_SUFFIXES = %w[@c.us @s.whatsapp.net].freeze
  LID_SUFFIX = '@lid'.freeze
  LABEL_COLOR = '#25D366'.freeze
  ID_KEYS = %w[id JID jid pn PhoneNumber phoneNumber lid LID].freeze
  NAME_KEYS = %w[DisplayName name pushName notify].freeze

  def initialize(list)
    @list = list
    @account = list.account
    @stats = Hash.new(0)
    @joined_contact_ids = []
  end

  def perform
    _inbox, @service = Whatsapp::WahaInboxResolver.new(@account).resolve!(@list.inbox_id)
    Contacts::BroadcastConsent.ensure_definition!(@account)
    now = Time.current
    participants = fetch_participants
    seen = participants.map { |participant| upsert_member(participant, now).id }
    mark_left(seen, now)
    tag_contacts
    result = finish(now, participants.length)
    ContactLists::EntryNotifier.call(@list, @joined_contact_ids)
    result
  end

  private

  def fetch_participants
    own = digits_of(@service.own_chat_id)
    @service.group_participants(@list.group_identifier)
            .filter_map { |raw| normalize(raw) }
            .reject { |participant| own.present? && digits_of(participant[:phone_jid]) == own }
            .uniq { |participant| participant[:wa_id] }
  end

  # Aceita a v2 normalizada ({id, role}) e a v1 crua do GOWS ({JID,
  # PhoneNumber, LID, IsAdmin, IsSuperAdmin, DisplayName}) ou do WEBJS
  # ({id: {_serialized}, isAdmin}).
  def normalize(raw)
    raw = raw.to_h
    return if raw['role'] == 'left'

    phone_jid, lid = split_jids(raw.values_at(*ID_KEYS).filter_map { |value| clean_jid(value) })
    return if phone_jid.blank? && lid.blank?

    { wa_id: phone_jid || lid, phone_jid: phone_jid, lid: lid, role: role_of(raw), name: raw.values_at(*NAME_KEYS).find(&:present?) }
  end

  # O primeiro jid de telefone (como "5531…@c.us") e o primeiro LID.
  def split_jids(ids)
    phone_jid = ids.find { |jid| jid.end_with?(*PHONE_SUFFIXES) }
    [phone_jid && "#{digits_of(phone_jid)}@c.us", ids.find { |jid| jid.end_with?(LID_SUFFIX) }]
  end

  # "5531…:12@s.whatsapp.net" (com o aparelho) e {_serialized: "…"} viram o jid puro.
  def clean_jid(value)
    value = value['_serialized'] if value.is_a?(Hash)
    return if value.blank? || !value.is_a?(String) || value.exclude?('@')

    user, server = value.split('@', 2)
    "#{user.split(':').first}@#{server}"
  end

  def role_of(raw)
    return raw['role'] if raw['role'].present?
    return 'superadmin' if raw['IsSuperAdmin'] || raw['isSuperAdmin']
    return 'admin' if raw['IsAdmin'] || raw['isAdmin']

    'participant'
  end

  def upsert_member(participant, now)
    participant[:phone_jid] ||= resolve_lid(participant[:lid])
    contact = find_or_create_contact(participant)
    member = find_member(participant, contact)
    joined = member.new_record? || member.status_left?
    member.assign_attributes(contact: contact, wa_id: participant[:phone_jid] || participant[:lid], role: participant[:role],
                             display_name: participant[:name].presence || member.display_name, status: :active, left_at: nil)
    member.joined_at = now if joined
    count(member, joined)
    member.save!
    member
  end

  # "Entrou" só conta no resumo numa atualização (na primeira extração todos
  # são novos); o gatilho do Chatflow vale para as duas.
  def count(member, joined)
    @joined_contact_ids << member.contact_id if joined && member.contact_id
    @stats[:joined] += 1 if joined && @list.refreshed_at.present?
    @stats[:no_phone] += 1 if member.contact&.phone_number.blank?
  end

  def resolve_lid(lid)
    return if lid.blank?

    pn = @service.find_phone_by_lid(lid).to_h['pn']
    @stats[:lids_resolved] += 1 if pn.present?
    clean_jid(pn)
  end

  def find_member(participant, contact)
    ids = [participant[:wa_id], participant[:phone_jid], participant[:lid]].compact.uniq
    @list.members.find_by(wa_id: ids) || (contact && @list.members.find_by(contact_id: contact.id)) || @list.members.new
  end

  def find_or_create_contact(participant)
    phone = participant[:phone_jid] && Broadcasts::PhoneNumber.normalize(digits_of(participant[:phone_jid]))
    contact = phone && @account.contacts.where(phone_number: Broadcasts::PhoneNumber.variants(phone)).order(:id).first
    contact ||= contact_by_lid(participant[:lid])
    return attach_phone(contact, phone) if contact
    return if phone.blank?

    create_contact(participant, phone)
  end

  def contact_by_lid(lid)
    return if lid.blank?

    @account.contacts.where(identifier: lid).or(@account.contacts.where("contacts.custom_attributes->>'waha_whatsapp_lid' = ?", lid)).order(:id).first
  end

  # Contato de LID que a ponte criou sem número: a WAHA acabou de dizer qual é.
  def attach_phone(contact, phone)
    contact.update!(phone_number: phone) if phone.present? && contact.phone_number.blank?
    contact
  end

  def create_contact(participant, phone)
    attributes = { Contacts::BroadcastConsent::ATTRIBUTE => false, 'waha_whatsapp_jid' => participant[:phone_jid],
                   'waha_whatsapp_lid' => participant[:lid] }.compact
    @stats[:created] += 1
    @account.contacts.create!(name: participant[:name].presence || phone, phone_number: phone, custom_attributes: attributes)
  end

  def mark_left(seen_ids, now)
    # rubocop:disable Rails/SkipsModelValidations
    @stats[:left] = @list.members.status_active.where.not(wa_id: nil).where.not(id: seen_ids)
                         .update_all(status: ContactListMember.statuses[:left], left_at: now, updated_at: now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def tag_contacts
    title = label_title
    @account.labels.find_or_create_by!(title: title) do |label|
      label.color = LABEL_COLOR
      label.description = I18n.t('contact_lists.group.label_description', name: group_name)
    end
    Contact.where(id: @list.members.status_active.where.not(contact_id: nil).select(:contact_id)).find_each do |contact|
      contact.add_labels([title]) unless contact.label_list.include?(title)
    end
    @list.metadata = @list.metadata.merge('label' => title)
  end

  def label_title
    return @list.metadata['label'] if @list.metadata['label'].present?

    slug = group_name.parameterize.presence || digits_of(@list.group_identifier)
    "grupo-#{slug}".truncate(60, omission: '')
  end

  def group_name
    @group_name ||= @list.metadata['group_name'].presence || @list.name
  end

  def finish(now, total)
    @list.update!(status: 'ready', last_error: nil, refreshed_at: now, members_count: @list.members.status_active.count,
                  metadata: @list.metadata.merge('last_run' => @stats.merge('total' => total, 'at' => now.to_i)))
    @stats
  end

  def digits_of(jid)
    jid.to_s.split('@').first.to_s.gsub(/\D/, '')
  end
end
