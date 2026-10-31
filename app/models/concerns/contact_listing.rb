# What narrows the contact list: who counts as a contact, and the free-text search.
module ContactListing
  extend ActiveSupport::Concern

  MIN_PHONE_SEARCH_DIGITS = 4

  class_methods do
    def resolved_contacts(use_crm_v2: false)
      return where(contact_type: 'lead') if use_crm_v2

      where("contacts.email <> '' OR contacts.phone_number <> '' OR contacts.identifier <> ''")
    end

    # Digits are matched on their own so "(31) 99865-1793" finds +5531998651793.
    def matching_text(query)
      term = query.strip
      digits = term.gsub(/\D/, '')
      conditions = 'contacts.name ILIKE :search OR contacts.email ILIKE :search OR contacts.phone_number ILIKE :search ' \
                   'OR contacts.identifier LIKE :search'
      conditions += ' OR contacts.phone_number LIKE :digits' if digits.length >= MIN_PHONE_SEARCH_DIGITS
      where(conditions, search: "%#{term}%", digits: "%#{digits}%")
    end
  end
end
