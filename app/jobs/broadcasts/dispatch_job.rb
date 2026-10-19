# Drives a running broadcast through its recipients using an adaptive,
# human-like throttle. The job re-enqueues itself between batches so the
# dispatch is spread out over time instead of hammering WAHA in one burst.
class Broadcasts::DispatchJob < ApplicationJob
  queue_as :low

  def perform(broadcast_id)
    @broadcast = Broadcast.find_by(id: broadcast_id)
    return if @broadcast.nil? || !@broadcast.status_running?

    build_recipients
    return if daily_cap_reached?

    send_batch
    @broadcast.broadcast_recipients.status_pending.exists? ? schedule_next : @broadcast.status_completed!
  end

  private

  # Adds every contact the audience resolves to that is not a recipient yet.
  # It runs on every batch, not only the first: a campaign tested on one
  # contact and relaunched after the operator added a hundred more has to pick
  # those hundred up. The old early return on `exists?` skipped them for good,
  # so the screen kept showing the single test send.
  def build_recipients
    resolver = Broadcasts::AudienceResolver.new(@broadcast)
    # Numbers typed straight into the composer have no contact row yet; without
    # this the whole cold list resolves to nothing and the broadcast reports
    # zero recipients instead of saying the list never landed.
    resolver.ensure_contacts!
    audience = resolver.contact_ids
    return if audience.empty?

    # Under a row lock because there is no unique index on
    # (broadcast_id, contact_id): two overlapping runs — a relaunch while the
    # previous dispatch is still going — would otherwise compute the same diff
    # and send the same contact twice.
    @broadcast.with_lock do
      fresh = audience - @broadcast.broadcast_recipients.pluck(:contact_id)
      insert_recipients(fresh) if fresh.any?
    end
  end

  def insert_recipients(contact_ids)
    now = Time.current
    rows = contact_ids.map do |contact_id|
      { broadcast_id: @broadcast.id, contact_id: contact_id, status: 0, created_at: now, updated_at: now }
    end
    # Bulk insert is intentional — no per-row callbacks needed when seeding recipients.
    # rubocop:disable Rails/SkipsModelValidations
    @broadcast.broadcast_recipients.insert_all(rows)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def send_batch
    size = rand(@broadcast.batch_min..@broadcast.batch_max)
    @broadcast.broadcast_recipients.status_pending.limit(size).each do |recipient|
      break if daily_cap_reached?

      Broadcasts::RecipientSenderService.new(recipient).perform
    end
  end

  def schedule_next
    delay = rand(@broadcast.delay_min..@broadcast.delay_max)
    self.class.set(wait: delay.seconds).perform_later(@broadcast.id)
  end

  def daily_cap_reached?
    sent_today = @broadcast.broadcast_recipients
                           .where('sent_at >= ?', Time.current.beginning_of_day)
                           .count
    return false if sent_today < @broadcast.daily_cap

    self.class.set(wait_until: Time.current.tomorrow.change(hour: 9)).perform_later(@broadcast.id)
    true
  end
end
