# Resolves a broadcast's audience JSON into a de-duplicated list of contact ids.
# Each filter is optional; the final audience is the UNION of every filter that
# is present. Only contacts with a phone number are eligible (WAHA send mode).
#
# Segment filters (origem, recorrente, sem resposta há X dias, aniversariantes,
# etiquetas a excluir) NARROW that union instead of adding to it. Used alone,
# they narrow the whole contact base: "recorrentes sem resposta há 60 dias".
class Broadcasts::AudienceResolver
  DEFAULT_COUNTRY_CODE = '55'.freeze
  INCLUDE_KEYS = %w[contact_label_ids conversation_label_ids funnel_stage_ids contact_ids phone_numbers].freeze
  BIRTHDAY_ATTRIBUTE = 'data_nascimento'.freeze

  def initialize(broadcast)
    @broadcast = broadcast
    @account = broadcast.account
    @filters = broadcast.audience_filters
  end

  def contact_ids
    ids = from_contact_labels +
          from_conversation_labels +
          from_funnel_stages +
          from_manual_ids +
          from_phone_numbers

    with_phone(refine(ids.uniq))
  end

  # Typed numbers that have no contact yet. They are real recipients, so the
  # preview counts them and the dispatch creates them before resolving ids.
  def missing_phone_numbers
    return [] if normalized_phone_numbers.empty?

    normalized_phone_numbers - @account.contacts.where(phone_number: normalized_phone_numbers).pluck(:phone_number)
  end

  # Called by the dispatch only — never by the preview, which must not write.
  def ensure_contacts!
    missing_phone_numbers.each do |number|
      @account.contacts.create!(name: number, phone_number: number)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[Broadcast audience] skipped #{number}: #{e.message}")
    end
  end

  private

  def from_contact_labels
    ids = Array(@filters['contact_label_ids']).map(&:to_i).reject(&:zero?)
    return [] if ids.empty?

    titles = @account.labels.where(id: ids).pluck(:title)
    return [] if titles.empty?

    @account.contacts.tagged_with(titles, any: true).pluck(:id)
  end

  def from_conversation_labels
    ids = Array(@filters['conversation_label_ids']).map(&:to_i).reject(&:zero?)
    return [] if ids.empty?

    titles = @account.labels.where(id: ids).pluck(:title)
    return [] if titles.empty?

    @account.conversations.tagged_with(titles, any: true).pluck(:contact_id)
  end

  def from_funnel_stages
    ids = Array(@filters['funnel_stage_ids']).map(&:to_i).reject(&:zero?)
    return [] if ids.empty?

    task_ids = @account.kanban_tasks.where(funnel_stage_id: ids).select(:id)
    Conversation.joins(:kanban_task_conversations)
                .where(kanban_task_conversations: { kanban_task_id: task_ids })
                .pluck(:contact_id)
  end

  def from_manual_ids
    Array(@filters['contact_ids']).map(&:to_i).reject(&:zero?)
  end

  def from_phone_numbers
    return [] if normalized_phone_numbers.empty?

    @account.contacts.where(phone_number: normalized_phone_numbers).pluck(:id)
  end

  # A pasted list arrives raw: "(11) 99999-8888", "11999998888", "5511999998888".
  # Matching those against the stored "+5511999998888" as typed is why a cold
  # list used to resolve to zero recipients without saying so.
  def normalized_phone_numbers
    @normalized_phone_numbers ||= Array(@filters['phone_numbers']).filter_map { |n| normalize_phone(n) }.uniq
  end

  # Reuses the normalizer the WhatsApp webhook already applies, so a number
  # typed here ends up in the same shape the provider will send back. Inventing
  # a second convention is how the reply to a broadcast opens its own separate
  # conversation instead of landing in the one the dispatch created.
  def normalize_phone(raw)
    digits = raw.to_s.gsub(/\D/, '')
    return if digits.length < 10

    digits = "#{DEFAULT_COUNTRY_CODE}#{digits}" if local_number?(raw, digits)
    return "+#{digits}" unless brazilian_mobile?(digits)

    "+#{Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(digits)}"
  end

  # A leading + means the number already carries its country code. Adding 55 to
  # everything short turned a US number into a Brazilian one, so the + is the
  # contract: international numbers are typed with it.
  def local_number?(raw, digits)
    digits.length <= 11 && !raw.to_s.strip.start_with?('+')
  end

  # The normalizer inserts the ninth digit whenever the result is not 13 long,
  # which turns a 10-digit landline into somebody else's mobile. Only a number
  # that already looks like a Brazilian mobile is handed to it.
  def brazilian_mobile?(digits)
    return false unless digits.start_with?(DEFAULT_COUNTRY_CODE)

    digits.length == 13 || (digits.length == 12 && digits[4].to_i >= 6)
  end

  def with_phone(ids)
    return [] if ids.empty?

    @account.contacts.where(id: ids).where.not(phone_number: [nil, '']).pluck(:id)
  end

  def refine(ids)
    return ids unless refining?

    scope = include_filters? ? @account.contacts.where(id: ids) : @account.contacts
    scope = by_origin(scope)
    scope = by_recurring(scope)
    scope = by_silence(scope)
    scope = without_labels(scope)
    by_birthday(scope.pluck(:id))
  end

  def refining?
    %w[origins recurring no_reply_days birthday exclude_label_ids].any? { |key| @filters[key].present? }
  end

  def include_filters?
    INCLUDE_KEYS.any? { |key| Array(@filters[key]).any? }
  end

  # origem_lead do contato: anuncio_facebook / organico (Contacts::OriginService).
  def by_origin(scope)
    origins = Array(@filters['origins']).compact_blank
    origins.any? ? scope.where("contacts.custom_attributes->>'origem_lead' IN (?)", origins) : scope
  end

  def by_recurring(scope)
    case @filters['recurring'].to_s
    when 'yes' then scope.where("contacts.custom_attributes->>'recorrente' = 'true'")
    when 'no' then scope.where("COALESCE(contacts.custom_attributes->>'recorrente', 'false') <> 'true'")
    else scope
    end
  end

  # Já conversou com o salão, mas não escreve há pelo menos X dias.
  def by_silence(scope)
    days = @filters['no_reply_days'].to_i
    return scope if days <= 0

    incoming = Message.where(account_id: @account.id, message_type: :incoming).joins(:conversation)
    scope.where(id: incoming.select('conversations.contact_id'))
         .where.not(id: incoming.where(created_at: days.days.ago..).select('conversations.contact_id'))
  end

  def without_labels(scope)
    ids = Array(@filters['exclude_label_ids']).map(&:to_i).reject(&:zero?)
    titles = ids.any? ? @account.labels.where(id: ids).pluck(:title) : []
    return scope if titles.empty?

    scope.where.not(id: @account.contacts.tagged_with(titles, any: true).pluck(:id))
         .where.not(id: @account.conversations.tagged_with(titles, any: true).pluck(:contact_id))
  end

  # today / week (próximos 7 dias) / month, pelo data_nascimento do contato.
  def by_birthday(ids)
    period = @filters['birthday'].to_s
    return ids if period.blank? || ids.empty?

    days = birthday_days(period)
    @account.contacts.where(id: ids).where("contacts.custom_attributes->>'#{BIRTHDAY_ATTRIBUTE}' IS NOT NULL")
            .pluck(:id, Arel.sql("contacts.custom_attributes->>'#{BIRTHDAY_ATTRIBUTE}'"))
            .filter_map { |id, raw| id if days.include?(month_day(raw)) }
  end

  def birthday_days(period)
    today = Time.current.in_time_zone(Broadcasts::SendWindow.default_for(@account).zone).to_date
    range = case period
            when 'week' then today..(today + 6)
            when 'month' then today.all_month
            else today..today
            end
    range.map { |date| [date.month, date.day] }
  end

  def month_day(raw)
    date = Date.parse(raw.to_s)
    [date.month, date.day]
  rescue ArgumentError
    nil
  end
end
