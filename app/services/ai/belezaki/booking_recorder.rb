# What the agent booked on the salon's agenda, written down on our side.
#
# The salon holds the book, so until now a belezaki booking left no trace here
# at all: the agent marked a real appointment, took a real price, and the
# account panel had nothing to show for it. Every commercial number the module
# reports was blind to the one agenda that books the most.
#
# Everything needed was already coming back in the response and being handed to
# the model and then dropped — the appointment id, the start, the service, the
# professional and the price in cents.
#
# ONE ROW PER APPOINTMENT, never one per event. `external_ref` carries the
# salon's own appointment id and the table has a unique index on
# (account_id, external_ref), which is exactly what that index was built for:
#
#   * booking confirmed -> the row is created with the price the salon QUOTED;
#   * comanda opened    -> the SAME row is updated to what was actually BILLED,
#     because the till is what happened and the quote was a promise;
#   * cancelled         -> the row goes, because a cancelled appointment was
#     never money and leaving it there inflates the one figure an operator
#     repeats to somebody else.
#
# Nothing here may break a booking. The customer has already been told they have
# a time; failing to write our own bookkeeping is our problem, not theirs, so
# every path is rescued and logged.
class Ai::Belezaki::BookingRecorder
  SOURCE = 'agendamento'.freeze
  # Written by the agent itself, which is a value the model already allowed and
  # nothing had ever produced.
  RECORDER = 'agent'.freeze
  REF_PREFIX = 'belezaki:appointment:'.freeze

  def initialize(connection:, conversation: nil)
    @connection = connection
    @conversation = conversation
  end

  def booked(appointment)
    return unless appointment.is_a?(Hash)

    record(appointment['id']) do |event|
      event.amount_brl = reais(appointment['price_cents'])
      event.metadata = event.metadata.merge(
        'state' => 'booked', 'service' => appointment['service'],
        'professional' => appointment['professional'], 'starts_at' => appointment['start']
      )
    end
  end

  # The amount is only overwritten when the till actually gave one. A comanda
  # that answers without a total must not silently zero a real sale.
  def billed(appointment_id, total_cents)
    record(appointment_id) do |event|
      event.amount_brl = reais(total_cents) if total_cents.present?
      event.metadata = event.metadata.merge('state' => 'billed')
    end
  end

  def cancelled(appointment_id)
    return if appointment_id.blank? || scope.nil?

    scope.find_by(external_ref: ref(appointment_id))&.destroy!
  rescue StandardError => e
    warn_about(appointment_id, e)
  end

  private

  def record(appointment_id)
    return if appointment_id.blank? || scope.nil?

    event = scope.find_or_initialize_by(external_ref: ref(appointment_id))
    event.assign_attributes(attribution)
    # Only on the way in. A comanda opened the next morning must not move a sale
    # out of the night it was taken in, which is the whole basis of the
    # after-hours figure.
    event.occurred_at ||= Time.current
    yield event
    event.save!
  rescue StandardError => e
    warn_about(appointment_id, e)
  end

  # Nil when the tools were built without a connection, which is the case in the
  # playground and in tests. There is no account to attribute to, so there is
  # nothing to write.
  def scope
    return nil if @connection.nil?

    @scope ||= Ai::RevenueEvent.where(account_id: @connection.account_id)
  end

  def attribution
    {
      account_id: @connection.account_id,
      ai_assistant_id: @connection.ai_assistant_id,
      conversation_id: @conversation&.id,
      contact_id: @conversation&.contact_id,
      source: SOURCE,
      recorded_by: RECORDER
    }
  end

  def ref(appointment_id)
    "#{REF_PREFIX}#{appointment_id}"
  end

  def reais(cents)
    (cents.to_i / 100.0).round(2)
  end

  def warn_about(appointment_id, error)
    Rails.logger.error(
      "[Athenas belezaki] could not record appointment #{appointment_id}: #{error.class}: #{error.message}"
    )
    nil
  end
end
