# Stamps where a contact came from, once, on its first incoming message:
#   origem_lead = anuncio_facebook  when the contact arrived through a
#                                   Click-to-WhatsApp ad (a conversation of
#                                   theirs carries anuncio_id or the
#                                   lead-anuncio label);
#   origem_lead = organico          otherwise.
#
# Decision: no new `origem` attribute. The contact already has `origem_lead`
# ("Lead origin"), created by Conversations::AdReferralService and stamped
# with anuncio_facebook on the first ad touch; this service only fills the
# blank with organico. One key, two values, never overwritten: a customer who
# came from an ad stays an ad customer when they come back organically, and
# an organic customer who clicks an ad later stays organic (AdReferralService
# also leaves a filled value alone). The conversation keeps its own
# `origem_lead` (per conversation, ads only) untouched.
class Contacts::OriginService
  ATTRIBUTE = 'origem_lead'.freeze
  AD = Conversations::AdReferralService::ORIGIN
  AD_LABEL = Conversations::AdReferralService::LABEL
  ORGANIC = 'organico'.freeze

  def initialize(contact)
    @contact = contact
  end

  # Returns the value written, or nil when the contact already had one.
  def perform
    return nil if @contact.blank? || @contact.custom_attributes[ATTRIBUTE].present?

    ensure_definition
    origin = from_ad? ? AD : ORGANIC
    @contact.update!(custom_attributes: @contact.custom_attributes.merge(ATTRIBUTE => origin))
    origin
  end

  private

  def from_ad?
    conversations = @contact.conversations
    conversations.where("jsonb_exists(conversations.custom_attributes, 'anuncio_id')").exists? ||
      conversations.tagged_with(AD_LABEL, on: :labels).exists?
  end

  # Same definition AdReferralService creates; whoever runs first creates it.
  def ensure_definition
    @contact.account.custom_attribute_definitions.find_or_create_by!(attribute_key: ATTRIBUTE, attribute_model: 'contact_attribute') do |record|
      record.attribute_display_name = I18n.t('ad_referral.attributes.origem_lead')
      record.attribute_display_type = 'text'
      record.attribute_description = I18n.t('ad_referral.attributes.origem_lead_description')
    end
  end
end
