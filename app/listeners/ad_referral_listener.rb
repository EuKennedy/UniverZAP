# Reads the Click-to-WhatsApp ad block off every incoming message. Runs before
# the automation listener in the dispatcher so a `conversation.ad_referral`
# rule sees the parsed attributes; the Chatflow engine does its own cheap
# check on the raw text, so ordering never decides whether a flow starts.
class AdReferralListener < BaseListener
  def message_created(event)
    return if sandbox_event?(event)

    message = event.data[:message]
    return if message.blank? || !message.incoming? || message.private?

    Conversations::AdReferralService.new(message).perform
  end
end
