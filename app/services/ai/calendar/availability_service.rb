# What the agent is allowed to offer, and nothing else.
#
# Four filters, in this order, and each one exists because its absence is felt
# in the first week rather than in a demo:
#   1. the week the operator drew, as ranges so lunch is a real gap
#   2. minus everything Google says is busy, INCLUDING what the owner wrote by
#      hand, which is why we ask free/busy instead of only our own rows
#   3. inside the bookable window: never sooner than they can be ready, never
#      further out than they can plan for
#   4. sliced by duration PLUS buffer, because the chair is occupied longer
#      than the customer is told
#
# The arithmetic lives here and not in the prompt on purpose. Asked to add 90
# minutes to 14:00 the model gets it wrong the same way it used to get prices
# wrong, and a wrong time is a customer standing at a closed door.
class Ai::Calendar::AvailabilityService
  # Offers land on the quarter hour. Stepping by the service duration would make
  # the first free slot of the day the only one anybody is ever offered.
  SLOT_STEP_MINUTES = 15
  # Enough to answer "what do you have this week" without handing the model a
  # list it will summarise badly.
  MAX_SLOTS = 40

  def initialize(assistant:, service:, professional: nil, from: nil, to: nil)
    @assistant = assistant
    @service = service
    @professional = professional || assistant.calendar_professionals.active.first
    @from = from
    @to = to
  end

  # => [ActiveSupport::TimeWithZone] slot start times, in the agenda's own zone.
  def perform
    return [] if @professional.blank? || @service.blank?

    window = bookable_window
    return [] if window.begin >= window.end

    busy = busy_periods(window)
    candidates(window).reject { |slot| busy_at?(slot, busy) }.first(MAX_SLOTS)
  end

  private

  def setting
    @setting ||= @assistant.calendar_setting || Ai::Calendar::Setting.new
  end

  def zone
    @zone ||= ActiveSupport::TimeZone[@professional.timezone.to_s] || Time.zone
  end

  # The operator's rules intersected with whatever the caller asked for, so a
  # customer saying "quinta" narrows the search without ever widening it past
  # what the business allows.
  def bookable_window
    allowed = setting.bookable_range(Time.current)
    starts = [allowed.begin, @from].compact.max
    ends = [allowed.end, @to].compact.min
    starts..ends
  end

  def busy_periods(window)
    client.busy(calendar_id: @professional.calendar_id, from: window.begin, to: window.end)
  rescue Ai::Calendar::GoogleClient::Error => e
    # Offering a slot we could not verify is worse than offering none: it books
    # a customer on top of whatever the owner already had there.
    Rails.logger.error("[Athenas calendar] free/busy failed assistant=#{@assistant.id}: #{e.message}")
    raise
  end

  def client
    @client ||= Ai::Calendar::GoogleClient.new(@professional.connection)
  end

  def candidates(window)
    (window.begin.to_date..window.end.to_date).flat_map { |date| slots_on(date, window) }.sort
  end

  def slots_on(date, window)
    hours_by_weekday[date.wday].to_a.flat_map { |range| slots_in_range(date, range, window) }
  end

  def hours_by_weekday
    @hours_by_weekday ||= @professional.hours.order(:weekday, :starts_at).group_by(&:weekday)
  end

  def slots_in_range(date, range, window)
    opens = at(date, range.starts_at)
    closes = at(date, range.ends_at)
    slots = []
    cursor = opens
    while cursor + occupied <= closes
      slots << cursor if window.cover?(cursor)
      cursor += SLOT_STEP_MINUTES.minutes
    end
    slots
  end

  def at(date, clock)
    zone.local(date.year, date.month, date.day, clock.hour, clock.min)
  end

  # Duration plus buffer: the customer hears 90 minutes, the chair is held for
  # 90 plus the time to clean it. Without this the agent books 14:00 and 15:30
  # back to back and the second customer waits in the doorway.
  def occupied
    @occupied ||= @service.occupied_minutes.minutes
  end

  def busy_at?(slot, busy)
    finish = slot + occupied
    busy.any? { |period| slot < period.end && finish > period.begin }
  end
end
