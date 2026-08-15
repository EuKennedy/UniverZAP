# Executes a belezaki scheduling tool call. Schemas live next door in
# Ai::Belezaki::ToolDefinitions, the same split the Google calendar module uses.
#
# `call(name, input) -> String` never raises: a salon that refuses is data the
# model can act on, not an exception that costs the customer their reply. What
# comes back is normalised — `agendado`, `comanda_aberta`, `remarcado`,
# `desmarcado` — because the
# turn guard reads a completed write off those words, and belezaki answers in a
# shape that matches none of them.
class Ai::Belezaki::SchedulingTools
  # Schemas live in Ai::Belezaki::ToolDefinitions.
  def self.definitions(include_booking:)
    Ai::Belezaki::ToolDefinitions.all(include_booking: include_booking)
  end

  def initialize(client, scope:, contact: {}, connection: nil, conversation: nil)
    @client = client
    # Only so a booking can be attributed to the conversation that produced it.
    # Optional like the connection: the playground has neither, and a sandbox
    # turn must never write a sale.
    @conversation = conversation
    # Optional. When present, a salon that refuses the binding gets written down
    # on it, so the screen stops claiming "connected" while the agent has quietly
    # lost the ability to book.
    @connection = connection
    # Namespace for booking idempotency keys — keeps this conversation's
    # bookings from ever colliding with another conversation's on belezaki.
    @scope = scope
    # Contact record (name/phone) is the source of truth for who is booking;
    # the LLM-extracted fields are only a fallback.
    @contact = contact || {}
    @performed_write = false
  end

  # True once a write tool (booking) has been ATTEMPTED in this turn. Set before
  # the HTTP call on purpose: a timeout may still have created the appointment
  # on the salon side, so the caller must treat the turn as non-replayable
  # either way rather than risk a second booking.
  def performed_write?
    @performed_write
  end

  # Returns a JSON string for the tool_result. Never raises — belezaki errors
  # are returned as data so Claude can apologise/redirect gracefully.
  def call(name, input)
    input ||= {}
    result = dispatch(name, input)
    result.is_a?(String) ? result : result.to_json
  rescue Ai::Belezaki::AgentClient::Error => e
    salon_error(e)
  rescue StandardError => e
    # Never crash the tool loop / autopilot job — hand the error back to Claude
    # as data so it can apologise and continue.
    Rails.logger.error("[Athenas agent] tool #{name} failed: #{e.class}: #{e.message}")
    { error: 'tool_error', message: 'Não consegui completar essa ação agora.' }.to_json
  end

  private

  def salon_error(error)
    note_failure(error)
    { error: error.code.presence || 'belezaki_error', message: Ai::Belezaki::ErrorAdvice.for(error.code) }.to_json
  end

  # Failures worth putting on the operator's screen, as opposed to blips: 429,
  # 5xx and network errors were already retried, and stamping one on the card
  # would cry wolf for something that healed a second later.
  #
  # `entitlement_inactive` belongs here — the salon's subscription lapsed, which
  # will not heal on retry and which the operator cannot fix from this screen.
  CONFIG_FAILURES = %w[http_401 http_503 entitlement_inactive].freeze

  # Only a 404 revokes: the salon or the link itself is gone, and reconnecting is
  # exactly what repairs it. A 401, 503 or lapsed subscription is OUR shared key,
  # OUR configuration or their billing — every connection is affected at once,
  # and sending this one operator to reconnect fixes nothing while making it look
  # like their fault.
  #
  # Never raises: a screen that failed to update is not a reason to lose the
  # reply a customer is waiting for.
  def note_failure(error)
    return if @connection.blank?

    @connection.revoke!(error.message) if error.code == 'http_404'
    @connection.note_failure!(error.message) if CONFIG_FAILURES.include?(error.code)
  rescue StandardError => e
    Rails.logger.warn("[Belezaki] could not record agenda failure: #{e.message}")
  end

  READS = %w[listar_servicos listar_profissionais consultar_horarios sugerir_dias meus_agendamentos].freeze
  WRITES = %w[agendar abrir_comanda remarcar desmarcar].freeze

  # Split in two rather than one long case: reads and writes are different
  # risks, and the branch count of a single table crosses the complexity limit
  # the moment a ninth tool appears.
  def dispatch(name, input)
    invalid = invalid_input(name, input)
    return invalid if invalid
    return read(name, input) if READS.include?(name)
    return write(name, input) if WRITES.include?(name)

    { error: 'unknown_tool', message: "Ferramenta #{name} não existe." }
  end

  def read(name, input)
    case name
    when 'listar_servicos' then @client.services
    when 'listar_profissionais' then @client.professionals
    when 'consultar_horarios'
      @client.availability(service_id: input['service_id'], date: input['date'], professional_id: input['professional_id'])
    when 'sugerir_dias'
      @client.availability_month(service_id: input['service_id'], month: input['month'], professional_id: input['professional_id'])
    else mine
    end
  end

  def write(name, input)
    case name
    when 'agendar' then book(input)
    when 'abrir_comanda' then open_comanda(input)
    when 'remarcar' then reschedule(input)
    else cancel(input)
    end
  end

  # Checked here because the salon does NOT check it, and the failure is silent
  # rather than loud: `date=2026-02-30` answers 200 with the real slots of March
  # 2nd under an envelope that says February 30th, so the agent would offer a day
  # that does not exist. A missing date is worse still — it reaches Prisma as NaN
  # and comes back 500.
  #
  # Deliberately NOT validating id formats: the ids come from the salon's own
  # tool results, and a hallucinated one would be shaped like a real one anyway.
  def invalid_input(name, input)
    case name
    when 'consultar_horarios'
      refuse('Data inválida. Use AAAA-MM-DD com um dia que exista.') unless real_date?(input['date'])
    when 'sugerir_dias'
      refuse('Mês inválido. Use AAAA-MM.') unless real_month?(input['month'])
    when 'agendar', 'remarcar'
      refuse('Horário inválido. Copie o campo start do slot escolhido.') unless parsable_time?(input['start'])
    end
  end

  def refuse(message)
    { error: 'invalid_input', message: message }
  end

  def real_date?(value)
    Date.strptime(value.to_s, '%Y-%m-%d').present?
  rescue Date::Error, TypeError
    false
  end

  def real_month?(value)
    Date.strptime(value.to_s, '%Y-%m').present?
  rescue Date::Error, TypeError
    false
  end

  def parsable_time?(value)
    Time.iso8601(value.to_s).present?
  rescue ArgumentError, TypeError
    false
  end

  def book(input)
    @performed_write = true
    confirmation(@client.create_appointment(
                   service_id: input['service_id'],
                   start: input['start'],
                   professional_id: input['professional_id'],
                   client: { name: booking_name(input), phone: booking_phone(input) },
                   source: 'whatsapp_agent',
                   idempotency_key: booking_idempotency_key(input)
                 ))
  end

  # Two things at once, and both matter.
  #
  # `agendado` is what the turn guard reads to tell a real confirmation from a
  # model describing a call it was about to make. belezaki answers
  # `{"appointment": {"status": "confirmed"}}`, which matches nothing, so without
  # this every SUCCESSFUL booking would have its reply thrown away.
  #
  # And the status is checked rather than the HTTP code, because a replay of an
  # idempotency key whose appointment was cancelled also answers 201 — with
  # `"status": "canceled"`. Treating that as success tells a customer they have a
  # time that nobody is holding.
  def confirmation(response)
    appointment = response.is_a?(Hash) ? response['appointment'] : nil
    return { agendado: false, motivo: 'o salão não confirmou o agendamento' } unless appointment.is_a?(Hash)
    return { agendado: false, motivo: "situação do agendamento: #{appointment['status']}" } unless confirmed?(appointment)

    # The salon holds the book, so this is the only moment the appointment is
    # ours to write down. Everything the commercial panel needs is in this hash
    # and used to be dropped on the floor the instant the model had read it.
    recorder.booked(appointment)

    # `valor_centavos` is what the agent must say out loud before opening the
    # comanda. Quoting the catalogue instead is how a customer hears one number
    # and the till takes another.
    { agendado: true, id: appointment['id'], inicio: appointment['start'],
      servico: appointment['service'], profissional: appointment['professional'],
      valor_centavos: appointment['price_cents'] }
  end

  def confirmed?(appointment)
    appointment['status'].to_s == 'confirmed'
  end

  # The phone is the scope: the salon answers 404 for an appointment belonging to
  # anyone else, so this is also what keeps the agent off other people's agendas.
  def mine
    phone = booking_phone({})
    # A conversation with no number on the contact (web widget, for instance)
    # cannot be scoped, and asking the salon without one would either error or,
    # worse, be answered for somebody else.
    return refuse('Não tenho o WhatsApp deste cliente. Peça o número com DDD antes de consultar.') if phone.blank?

    @client.appointments(phone: phone)
  end

  # `changed: false` means the appointment was ALREADY at that time. That is the
  # outcome the customer asked for, so it is success — and it is what makes a
  # retry safe without an idempotency key.
  def reschedule(input)
    @performed_write = true
    response = @client.reschedule_appointment(
      input['appointment_id'],
      client_phone: booking_phone(input), start: input['start'], professional_id: input['professional_id']
    )
    { remarcado: true, quando: appointment_of(response)&.dig('start') }
  end

  # The salon answers {"comanda": {...}, "confirmado": true} — a shape the turn
  # guard reads as no write at all. Normalised like the others, so a successful
  # billing record is not suppressed as a false confirmation.
  #
  # Idempotent on the salon side: a nervous retry, or a client switching from PIX
  # to cash, updates the same comanda instead of opening a second one.
  def open_comanda(input)
    @performed_write = true
    response = @client.open_comanda(
      input['appointment_id'],
      client_phone: booking_phone(input), payment_method: input['forma_pagamento']
    )
    comanda = response.is_a?(Hash) ? response['comanda'] : nil
    # The till is what actually happened; the price quoted at booking was a
    # promise. Same row, keyed by the same appointment id, so the figure gets
    # truer without ever being counted twice.
    recorder.billed(input['appointment_id'], comanda&.dig('total_cents'))
    {
      comanda_aberta: true,
      valor_centavos: comanda&.dig('total_cents'),
      forma_pagamento: comanda&.dig('intended_payment_method')
    }
  end

  def cancel(input)
    @performed_write = true
    @client.cancel_appointment(
      input['appointment_id'], client_phone: booking_phone(input), reason: input['reason']
    )
    # A cancelled appointment was never money, and leaving it behind inflates
    # the one figure an operator repeats to somebody else.
    recorder.cancelled(input['appointment_id'])
    { desmarcado: true }
  end

  def recorder
    @recorder ||= Ai::Belezaki::BookingRecorder.new(connection: @connection, conversation: @conversation)
  end

  def appointment_of(response)
    response.is_a?(Hash) ? response['appointment'] : nil
  end

  # Idempotency must key on the ACTION (this specific appointment), not on the
  # conversation tick. Hashing service + start + professional + phone means:
  #   - a re-book of the SAME slot (client confirms again in a later turn)
  #     yields the SAME key, so belezaki dedups it (no duplicate booking);
  #   - two DIFFERENT bookings in the same turn ("corte terca e escova quinta")
  #     get DIFFERENT keys, so both go through.
  # The old "conv-<id>-<maxmsgid>" key did the opposite on both counts.
  def booking_idempotency_key(input)
    action = [input['service_id'], input['start'], input['professional_id'], booking_phone(input)].join('|')
    "#{@scope}:#{Digest::SHA256.hexdigest(action)[0, 24]}"
  end

  # Contact record wins over whatever the model extracted from the chat text, so
  # a hallucinated / mistyped name or number never lands in the salon's agenda.
  def booking_name(input)
    @contact[:name].presence || input['client_name']
  end

  def booking_phone(input)
    @contact[:phone].presence || input['client_phone']
  end
end
