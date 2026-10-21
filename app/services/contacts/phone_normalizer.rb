# Turns a phone typed by a person (a broadcast list, a store checkout) into the
# E.164 shape the WhatsApp webhook stores on contacts, so a lookup finds the
# contact the provider created and a reply lands in the same conversation.
# Brazilian mobiles get the ninth digit through the provider's normalizer.
module Contacts::PhoneNormalizer
  DEFAULT_COUNTRY_CODE = '55'.freeze

  module_function

  def normalize(raw)
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
end
