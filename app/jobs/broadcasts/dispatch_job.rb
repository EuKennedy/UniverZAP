# Drives a running broadcast through its recipients using an adaptive,
# human-like throttle. The job re-enqueues itself between batches so the
# dispatch is spread out over time instead of hammering WAHA in one burst.
#
# Anti-bloqueio (número não oficial), em ordem de checagem:
#   - só dentro da janela comercial do salão (fora dela, dorme até a abertura);
#   - teto por hora e por dia POR CONEXÃO, somando todos os disparos e
#     sequências daquela inbox;
#   - uma mensagem por vez com intervalo aleatório e, de vez em quando, um
#     respiro mais longo — ritmo de gente, não de robô;
#   - pula quem pediu opt-out ou falou/foi atendido nas últimas `quiet_hours`;
#   - pausa sozinho depois de `max_failures` falhas seguidas (ou falha demais
#     no geral): falha em série costuma ser a sessão caindo ou o número sob
#     restrição, e insistir é o que transforma restrição em banimento.
class Broadcasts::DispatchJob < ApplicationJob
  queue_as :low

  BREATHER_CHANCE = 12
  BREATHER = 300..600
  WINDOW_JITTER = 0..900
  HOURLY_RETRY = 600..1200
  FAILURE_RATE_MIN_SAMPLE = 5
  FAILURE_RATE_LIMIT = 0.3
  # Quantos destinatários pulados (opt-out, em atendimento) um lote atravessa
  # antes de dar a vez ao próximo job.
  SCAN_LIMIT = 50
  TOKEN_TTL = 30.days

  # Cada lançamento gera um token; cada job da corrente carrega o seu. Relançar
  # ou retomar depois de pausar deixaria a corrente antiga (que dormia até a
  # janela abrir) viva ao lado da nova — o dobro do ritmo no mesmo número.
  # Job sem token (enfileirado antes deste código) segue valendo.
  def self.start(broadcast, wait_until: nil)
    token = SecureRandom.hex(8)
    Redis::Alfred.setex(token_key(broadcast.id), token, TOKEN_TTL)
    set(wait_until: wait_until).perform_later(broadcast.id, token)
  end

  def self.token_key(broadcast_id)
    "broadcast:#{broadcast_id}:dispatch_token"
  end

  def perform(broadcast_id, token = nil)
    @token = token
    @broadcast = Broadcast.find_by(id: broadcast_id)
    return unless runnable?

    build_recipients
    return if waiting?

    send_batch
    return pause!('failures') if too_many_failures?

    @broadcast.broadcast_recipients.status_pending.exists? ? schedule_next : @broadcast.status_completed!
  end

  private

  def runnable?
    return false if @broadcast.nil? || stale?

    start_if_due && @broadcast.status_running?
  end

  def stale?
    @token.present? && Redis::Alfred.get(self.class.token_key(@broadcast.id)) != @token
  end

  # Nobody ready yet, window closed or connection capped: each of these
  # schedules its own wake-up and the batch is skipped.
  def waiting?
    return finish_or_wait || true unless @broadcast.broadcast_recipients.ready.exists?
    return wake_at(window.next_open + jitter) || true unless window.open?

    capped?
  end

  # A scheduled broadcast turns live once its time comes. A job enqueued for an
  # older scheduled_at (the operator moved it) finds the time not yet due and
  # does nothing: the job of the new time is the one that starts it.
  def start_if_due
    return true unless @broadcast.status_scheduled?
    return false if @broadcast.scheduled_at.present? && @broadcast.scheduled_at > 30.seconds.from_now

    @broadcast.update!(status: :running)
  end

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
    best = @broadcast.smart_timing? ? Broadcasts::BestTimeService.new(@broadcast.account, window: window).best_hours(contact_ids) : {}
    rows = contact_ids.map do |contact_id|
      send_after = best[contact_id] && window.next_at_hour(best[contact_id], after: now)
      { broadcast_id: @broadcast.id, contact_id: contact_id, status: 0, send_after: send_after, created_at: now, updated_at: now }
    end
    # Bulk insert is intentional — no per-row callbacks needed when seeding recipients.
    # rubocop:disable Rails/SkipsModelValidations
    @broadcast.broadcast_recipients.insert_all(rows)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # Nothing ready now: either everyone was processed, or the rest waits for
  # its best time (smart timing) — then sleep until the first of them.
  def finish_or_wait
    next_at = @broadcast.broadcast_recipients.status_pending.minimum(:send_after)
    return @broadcast.status_completed! if next_at.nil?

    wake_at(next_at)
  end

  def send_batch
    target = rand(@broadcast.batch_min..[@broadcast.batch_max, @broadcast.batch_min].max)
    sent = 0
    @broadcast.broadcast_recipients.ready.includes(:contact).order(:id).limit(SCAN_LIMIT).each do |recipient|
      break if sent >= target || capped?(reschedule: false)

      reason = Broadcasts::RecipientGuard.new(contact: recipient.contact, quiet_hours: @broadcast.quiet_hours).skip_reason
      next recipient.update!(status: :skipped, skip_reason: reason) if reason

      Broadcasts::RecipientSenderService.new(recipient).perform
      sent += 1
    end
  end

  def schedule_next
    delay = rand(@broadcast.delay_min..[@broadcast.delay_max, @broadcast.delay_min].max)
    delay += rand(BREATHER) if rand(BREATHER_CHANCE).zero?
    self.class.set(wait: delay.seconds).perform_later(@broadcast.id, @token)
  end

  # Caps count every automated send on the connection, not only this
  # broadcast: two campaigns running together must not double the volume.
  def capped?(reschedule: true)
    if sent_on_inbox_since(day_start) >= @broadcast.daily_cap
      wake_at(window.next_open(day_start + 1.day) + jitter) if reschedule
      return true
    end
    return false if sent_on_inbox_since(1.hour.ago) < @broadcast.hourly_cap

    wake_at(rand(HOURLY_RETRY).seconds.from_now) if reschedule
    true
  end

  def sent_on_inbox_since(time)
    broadcasts = BroadcastRecipient.joins(:broadcast).where(broadcasts: { inbox_id: @broadcast.inbox_id }).where(sent_at: time..).count
    sequences = ScheduledMessage.status_sent.where(inbox_id: @broadcast.inbox_id).where.not(message_sequence_id: nil).where(sent_at: time..).count
    broadcasts + sequences
  end

  def too_many_failures?
    processed = @broadcast.broadcast_recipients.where(status: %i[sent delivered read failed])
    last = processed.order(updated_at: :desc, id: :desc).limit(@broadcast.max_failures).pluck(:status)
    return true if last.size >= @broadcast.max_failures && last.all?('failed')

    total = processed.count
    total >= FAILURE_RATE_MIN_SAMPLE && processed.status_failed.count.fdiv(total) > FAILURE_RATE_LIMIT
  end

  def pause!(reason)
    @broadcast.update!(status: :paused, pause_reason: reason)
  end

  def wake_at(time)
    self.class.set(wait_until: time).perform_later(@broadcast.id, @token)
  end

  def day_start
    Time.current.in_time_zone(window.zone).beginning_of_day
  end

  def jitter
    rand(WINDOW_JITTER).seconds
  end

  def window
    @window ||= @broadcast.send_window
  end
end
