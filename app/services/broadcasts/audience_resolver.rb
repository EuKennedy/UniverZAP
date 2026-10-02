# Resolves a broadcast's audience JSON into a de-duplicated list of contact ids.
# Each filter is optional; the final audience is the UNION of every filter that
# is present. Only contacts with a phone number are eligible (WAHA send mode).
class Broadcasts::AudienceResolver
  DEFAULT_COUNTRY_CODE = '55'.freeze

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

    with_phone(ids.uniq)
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
end
