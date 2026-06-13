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

  def build_recipients
    return if @broadcast.broadcast_recipients.exists?

    contact_ids = Broadcasts::AudienceResolver.new(@broadcast).contact_ids
    return if contact_ids.empty?

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
