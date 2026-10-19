# Turns the ad block that WAHA's Chatwoot App prepends to a Click-to-WhatsApp
# message into data the rest of the product can use.
#
# Nothing structured reaches us: WAHA renders `contextInfo.externalAdReply`
# through its `whatsapp.to.chatwoot.message.facebook.ad` template (pt-BR and
# en-US) and posts plain text through our API. So the ad id, title, body and
# link are read back out of that text here, once, and stored:
#   - on the message (`content_attributes.ad_referral`) for every ad message;
#   - on the conversation and contact as custom attributes on the FIRST ad
#     touch, when `conversation.ad_referral` fires. Later clicks only bump
#     `anuncio_cliques`: the lead keeps its first attribution.
class Conversations::AdReferralService
  LABEL = 'lead-anuncio'.freeze
  ORIGIN = 'anuncio_facebook'.freeze

  CONVERSATION_ATTRIBUTES = [
    %w[origem_lead text], %w[anuncio_id text], %w[anuncio_titulo text], %w[anuncio_url link], %w[anuncio_cliques number]
  ].freeze

  def self.ad_message?(content)
    Conversations::AdReferralParser.ad_message?(content)
  end

  def self.parse(content)
    return nil unless ad_message?(content)

    Conversations::AdReferralParser.new(content).data
  end

  def initialize(message)
    @message = message
    @conversation = message.conversation
    @account = message.account
  end

  def perform
    return unless @message.incoming? && !@message.private?

    data = self.class.parse(@message.content)
    return if data.nil?

    @message.update!(content_attributes: @message.content_attributes.merge('ad_referral' => data))
    first_touch? ? stamp_first_touch(data) : count_click
  end

  private

  def first_touch?
    @conversation.custom_attributes['anuncio_id'].blank?
  end

  def stamp_first_touch(data)
    ensure_definitions
    ensure_label
    @conversation.update!(custom_attributes: @conversation.custom_attributes.merge(
      'origem_lead' => ORIGIN, 'anuncio_id' => data['ad_id'], 'anuncio_titulo' => data['title'],
      'anuncio_url' => data['url'], 'anuncio_cliques' => 1
    ))
    stamp_contact
    Rails.configuration.dispatcher.dispatch(
      Events::Types::CONVERSATION_AD_REFERRAL, Time.zone.now,
      conversation: @conversation, message: @message, ad_referral: data
    )
  end

  def count_click
    attrs = @conversation.custom_attributes
    @conversation.update!(custom_attributes: attrs.merge('anuncio_cliques' => attrs['anuncio_cliques'].to_i + 1))
  end

  def stamp_contact
    contact = @conversation.contact
    return if contact.blank? || contact.custom_attributes['origem_lead'].present?

    contact.update!(custom_attributes: contact.custom_attributes.merge('origem_lead' => ORIGIN))
  end

  # Definitions make the attributes show up in the sidebar, in filters and as
  # automation conditions. Created once per account, never overwritten.
  def ensure_definitions
    CONVERSATION_ATTRIBUTES.each do |key, type|
      definition(key, 'conversation_attribute', type)
    end
    definition('origem_lead', 'contact_attribute', 'text')
  end

  def definition(key, model, type)
    @account.custom_attribute_definitions.find_or_create_by!(attribute_key: key, attribute_model: model) do |record|
      record.attribute_display_name = I18n.t("ad_referral.attributes.#{key}")
      record.attribute_display_type = type
      record.attribute_description = I18n.t("ad_referral.attributes.#{key}_description")
    end
  end

  def ensure_label
    @account.labels.find_or_create_by!(title: LABEL) do |label|
      label.color = '#2563EB'
      label.description = I18n.t('ad_referral.label_description')
      label.show_on_sidebar = true
    end
  end
end
