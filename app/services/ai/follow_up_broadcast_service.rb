# Turns a selection of leads from the radar into a real WhatsApp follow-up.
#
# It deliberately does NOT send anything itself. It builds a Broadcast and hands
# it to the dispatcher that already exists, because that dispatcher is where the
# anti-ban behaviour lives: randomised batch sizes, randomised delays and a
# daily cap. A second sending path would be a second place to get banned from.
class Ai::FollowUpBroadcastService
  class NoRecipients < StandardError; end
  class BlankMessage < StandardError; end
  class NoSendableInbox < StandardError; end

  # Channels WAHA can actually deliver a WhatsApp message through. Falling back
  # to "the first inbox" without this check would happily build a campaign
  # against a website widget or an e-mail inbox, mark every lead as followed up,
  # and deliver nothing.
  SENDABLE_CHANNELS = ['Channel::Whatsapp', 'Channel::Api'].freeze

  # Conservative next to the default broadcast throttle. A follow-up goes to
  # people who did NOT buy, so a burst of them is exactly the pattern WhatsApp
  # reads as spam.
  THROTTLE = { 'batch_min' => 2, 'batch_max' => 5, 'delay_min' => 45, 'delay_max' => 120 }.freeze

  def initialize(assistant:, opportunity_ids:, message:, inbox: nil)
    @assistant = assistant
    @account = assistant.account
    # `open_leads` only. A lead already marked won bought something, and one
    # marked lost was ruled out on purpose: messaging either is the fastest way
    # to make the radar look like spam.
    @opportunities = assistant.lead_opportunities.open_leads.where(id: opportunity_ids)
    @message = message.to_s.strip
    @inbox = inbox
  end

  def perform
    raise BlankMessage, 'a follow-up with no text creates conversations and says nothing' if @message.blank?

    inbox = sendable_inbox
    contact_ids = reachable_contact_ids
    raise NoRecipients, 'no open lead with a phone number in this selection' if contact_ids.empty?

    broadcast = build_broadcast(contact_ids, inbox)
    Broadcasts::DispatchJob.perform_later(broadcast.id)
    mark_followed!
    broadcast
  end

  private

  # WAHA can only reach a contact with a phone number, so a lead without one is
  # dropped here instead of failing silently inside the dispatcher.
  def reachable_contact_ids
    @account.contacts.where(id: @opportunities.select(:contact_id))
            .where.not(phone_number: [nil, '']).pluck(:id)
  end

  def build_broadcast(contact_ids, inbox)
    broadcast = @account.broadcasts.create!(
      name: "Follow-up #{@assistant.name} · #{Time.current.strftime('%d/%m %H:%M')}",
      inbox: inbox,
      message: { 'text' => @message },
      audience: { 'contact_ids' => contact_ids },
      throttle: THROTTLE
    )
    broadcast.status_running!
    broadcast
  end

  # The inbox the agent already answers on, so the follow-up arrives in the same
  # thread the customer remembers. Validated rather than assumed: an operator
  # whose agent sits on a widget inbox would otherwise get a campaign that marks
  # every lead as contacted and reaches nobody.
  def sendable_inbox
    candidate = @inbox || @assistant.inboxes.detect { |i| sendable?(i) } ||
                @account.inboxes.detect { |i| sendable?(i) }
    raise NoSendableInbox, 'no WhatsApp inbox to send this follow-up from' unless sendable?(candidate)

    candidate
  end

  def sendable?(inbox)
    inbox.present? && SENDABLE_CHANNELS.include?(inbox.channel_type)
  end

  # `followed`, not `won`: the message went out, the sale did not happen yet.
  # Conflating the two is how a radar starts reporting revenue that never came.
  def mark_followed!
    # rubocop:disable Rails/SkipsModelValidations
    @opportunities.update_all(status: 'followed', followed_up_at: Time.current, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
