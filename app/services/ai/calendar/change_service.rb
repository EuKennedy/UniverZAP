# Moving and cancelling an appointment the agent itself made.
#
# Both refuse inside the cancellation window, which is the operator's number
# and defaults to two hours. Past it the agent stops touching the agenda and a
# human decides: an automated no-show an hour before is a chair that stays
# empty and nobody could have stopped it.
#
# Only appointments in OUR index are reachable, which is what keeps the agent
# away from the dentist and the lunch the owner typed in by hand.
class Ai::Calendar::ChangeService
  class TooLate < StandardError; end
  class Unavailable < StandardError; end

  def initialize(appointment:)
    @appointment = appointment
    @professional = appointment.professional
  end

  def reschedule(starts_at)
    refuse_if_too_late!
    ends_at = starts_at + duration_minutes.minutes
    ensure_free!(starts_at, ends_at)

    client.update_event(
      calendar_id: @professional.calendar_id, event_id: @appointment.google_event_id,
      payload: { start: time_field(starts_at), end: time_field(ends_at) }
    )
    @appointment.update!(starts_at: starts_at, ends_at: ends_at)
    @appointment
  end

  # The row is KEPT and marked cancelled rather than deleted, so the agent can
  # answer "you had one on Thursday and it was cancelled" instead of drawing a
  # blank at the customer who is asking exactly that.
  def cancel
    refuse_if_too_late!
    client.delete_event(calendar_id: @professional.calendar_id, event_id: @appointment.google_event_id)
    @appointment.update!(status: 'cancelled')
    @appointment
  end

  private

  def refuse_if_too_late!
    window = @appointment.ai_assistant.calendar_setting&.cancellation_window_hours.to_i
    raise TooLate, 'perto demais do horário' if @appointment.within_cancellation_window?(window)
  end

  # The move must not land on top of something else, and the check happens here
  # rather than at offer time for the same reason booking re-checks: the owner
  # books from their phone in between.
  def ensure_free!(starts_at, ends_at)
    busy = client.busy(calendar_id: @professional.calendar_id, from: starts_at, to: ends_at)
    conflicting = busy.reject { |period| period.begin == @appointment.starts_at && period.end == @appointment.ends_at }
    return if conflicting.none? { |period| starts_at < period.end && ends_at > period.begin }

    raise Unavailable, 'horário ocupado'
  end

  # Kept from the original booking rather than recomputed from the services,
  # because a service may have been re-timed since, and moving an appointment
  # must not silently make it longer than what the customer agreed to.
  def duration_minutes
    ((@appointment.ends_at - @appointment.starts_at) / 60).round
  end

  def time_field(time)
    { dateTime: time.iso8601, timeZone: @professional.timezone }
  end

  def client
    @client ||= Ai::Calendar::GoogleClient.new(@professional.connection)
  end
end
