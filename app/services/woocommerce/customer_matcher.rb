# Finds the contact a store customer is: first by phone (normalized like the
# WhatsApp webhook stores it, ninth digit included), then by e-mail. A
# customer with a phone and no contact yet becomes one, so the next step
# (order messages) has somebody to write to. Without a usable phone or e-mail
# the order stays unlinked.
class Woocommerce::CustomerMatcher
  def initialize(account, billing)
    @account = account
    @phone = Broadcasts::PhoneNumber.normalize(billing['phone'])
    @email = billing['email'].to_s.strip.downcase.presence
    @name = [billing['first_name'], billing['last_name']].compact_blank.join(' ').presence
  end

  def perform
    by_phone || by_email || create_contact
  end

  private

  # Older contacts may be stored without the ninth digit.
  def by_phone
    @phone && @account.contacts.find_by(phone_number: Broadcasts::PhoneNumber.variants(@phone))
  end

  def by_email
    @email && @account.contacts.from_email(@email)
  end

  def create_contact
    return if @phone.nil?

    @account.contacts.create!(name: @name || @phone, phone_number: @phone, email: @email)
  rescue ActiveRecord::RecordInvalid
    # A malformed phone or an e-mail taken by another contact: link nothing
    # rather than guess.
    nil
  end
end
