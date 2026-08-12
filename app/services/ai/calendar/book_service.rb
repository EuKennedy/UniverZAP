# Writes the appointment into the owner's Google Calendar and keeps our index
# of it.
#
# Order matters and is deliberate: Google first, our row second. A row written
# before the event would point at nothing if Google refused, and the agent
# would then cheerfully offer to reschedule an appointment that was never made.
# The other way round, the worst case is an event on the agenda with no row,
# which the owner can see and delete.
class Ai::Calendar::BookService
  class Unavailable < StandardError; end
  class NothingToBook < StandardError; end

  # The agenda is optional: with one chair the caller omits it and gets the only
  # one there is. It is a parameter rather than a lookup so that the day a second
  # professional exists, the choice is made by the caller that knows who the
  # customer asked for, and not silently by `.first` here.
  def initialize(assistant:, contact:, services:, starts_at:, conversation: nil, professional: nil)
    @assistant = assistant
    @contact = contact
    @services = Array(services).compact
    @starts_at = starts_at
    @conversation = conversation
    @professional = professional || assistant.calendar_professionals.active.first
  end

  def perform
    raise NothingToBook, 'sem serviço' if @services.empty? || @professional.blank?

    ensure_still_free!
    event = client.create_event(calendar_id: @professional.calendar_id, payload: event_payload)
    persist(event)
  end

  private

  # Re-asked immediately before writing, and not only when the slot was offered.
  # Between the agent saying "14h está livre" and the customer saying "pode ser"
  # there are seconds in which the owner books somebody from their phone, and
  # Google has no insert-if-free.
  def ensure_still_free!
    busy = client.busy(calendar_id: @professional.calendar_id, from: @starts_at, to: ends_at)
    return if busy.none? { |period| @starts_at < period.end && ends_at > period.begin }

    raise Unavailable, 'horário ocupado'
  end

  def persist(event)
    appointment = Ai::Calendar::Appointment.create!(
      ai_calendar_professional_id: @professional.id, ai_assistant_id: @assistant.id,
      account_id: @assistant.account_id, contact_id: @contact.id, conversation_id: @conversation&.id,
      google_event_id: event['id'], starts_at: @starts_at, ends_at: ends_at, status: 'booked'
    )
    @services.each { |service| appointment.appointment_services.create!(ai_calendar_service_id: service.id) }
    appointment
  end

  # Duration is what the customer is told; the chair is held for duration plus
  # buffer. The buffer is applied ONCE, at the end: the room is turned around
  # after the last service, not between each one.
  def ends_at
    @ends_at ||= @starts_at + total_minutes.minutes
  end

  def total_minutes
    @services.sum(&:duration_minutes) + @services.map { |service| service.buffer_minutes.to_i }.max.to_i
  end

  # Short title, because the month view on a phone is where the owner actually
  # reads this. Everything else goes in the description, including the link back
  # to the conversation so they can see what was agreed.
  def event_payload
    {
      summary: "#{@services.map(&:name).join(' + ')} · #{@contact.name}",
      description: description,
      start: { dateTime: @starts_at.iso8601, timeZone: @professional.timezone },
      end: { dateTime: ends_at.iso8601, timeZone: @professional.timezone }
    }
  end

  def description
    [
      "Cliente: #{@contact.name}",
      ("Telefone: #{@contact.phone_number}" if @contact.phone_number.present?),
      "Profissional: #{@professional.name}",
      "Serviço: #{@services.map(&:name).join(' + ')}",
      conversation_url.presence,
      'Agendado pelo agente de IA da UniverZAP.'
    ].compact.join("\n")
  end

  def conversation_url
    return nil if @conversation.blank?

    @conversation_url ||= "#{ENV.fetch('FRONTEND_URL', '')}/app/accounts/#{@assistant.account_id}" \
                          "/conversations/#{@conversation.display_id}"
  end

  def client
    @client ||= Ai::Calendar::GoogleClient.new(@professional.connection)
  end
end
