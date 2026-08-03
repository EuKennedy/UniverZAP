# Turns a selection of leads from the radar into a real WhatsApp follow-up.
#
# It deliberately does NOT send anything itself. It builds a Broadcast and hands
# it to the dispatcher that already exists, because that dispatcher is where the
# anti-ban behaviour lives: randomised batch sizes, randomised delays and a
# daily cap. A second sending path would be a second place to get banned from.
class Ai::FollowUpBroadcastService
  class NoRecipients < StandardError; end

  # Conservative next to the default broadcast throttle. A follow-up goes to
  # people who did NOT buy, so a burst of them is exactly the pattern WhatsApp
  # reads as spam.
  THROTTLE = { 'batch_min' => 2, 'batch_max' => 5, 'delay_min' => 45, 'delay_max' => 120 }.freeze

  def initialize(assistant:, opportunity_ids:, message:, inbox: nil)
    @assistant = assistant
    @account = assistant.account
    @opportunities = assistant.lead_opportunities.where(id: opportunity_ids)
    @message = message.to_s.strip
    @inbox = inbox
  end

  def perform
    contact_ids = reachable_contact_ids
    raise NoRecipients, 'no lead with a phone number in this selection' if contact_ids.empty?

    broadcast = build_broadcast(contact_ids)
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

  def build_broadcast(contact_ids)
    broadcast = @account.broadcasts.create!(
      name: "Follow-up #{@assistant.name} · #{Time.current.strftime('%d/%m %H:%M')}",
      inbox: @inbox || default_inbox,
      message: { 'text' => @message },
      audience: { 'contact_ids' => contact_ids },
      throttle: THROTTLE
    )
    broadcast.status_running!
    broadcast
  end

  # The inbox the agent already answers on, so the follow-up arrives in the same
  # thread the customer remembers.
  def default_inbox
    @assistant.inboxes.first || @account.inboxes.first
  end

  # `followed`, not `won`: the message went out, the sale did not happen yet.
  # Conflating the two is how a radar starts reporting revenue that never came.
  def mark_followed!
    # rubocop:disable Rails/SkipsModelValidations
    @opportunities.update_all(status: 'followed', followed_up_at: Time.current, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
