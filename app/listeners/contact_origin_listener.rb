# Stamps the contact's origin on its first incoming message. Listed right
# after AdReferralListener in the dispatcher: for an ad message the ad service
# has already written anuncio_facebook on the contact, and this one only
# fills a blank with organico.
class ContactOriginListener < BaseListener
  def message_created(event)
    return if sandbox_event?(event)

    message = event.data[:message]
    return if message.blank? || !message.incoming? || message.private?

    Contacts::OriginService.new(message.conversation&.contact).perform
  end
end
