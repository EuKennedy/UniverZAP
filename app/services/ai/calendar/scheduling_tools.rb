# The agenda, executed. Schemas live in Ai::Calendar::ToolDefinitions.
#
# Same contract as Ai::Belezaki::SchedulingTools and Ai::CustomToolExecutor:
# `call(name, input) -> String`, never raises, and reports whether it wrote
# anything so a retried turn cannot book the same customer twice.
#
# The customer never sees any of this. They say "quinta às 14h" in the chat and
# the agent does the rest; Google sits between us and the OWNER, never between
# us and the customer.
class Ai::Calendar::SchedulingTools
  MAX_LISTED_SLOTS = 12
  WRITING_TOOLS = %w[agendar remarcar desmarcar].freeze

  def initialize(assistant:, contact:, conversation: nil)
    @assistant = assistant
    @contact = contact
    @conversation = conversation
    @performed_write = false
  end

  def performed_write?
    @performed_write
  end

  def call(name, input)
    # Set BEFORE the work, like the belezaki booking guard: a timeout may still
    # have created the event, so the turn is non-replayable either way.
    @performed_write = true if WRITING_TOOLS.include?(name)
    dispatch(name, (input || {}).with_indifferent_access)
  rescue Ai::Calendar::GoogleClient::Revoked
    error('A agenda foi desconectada. Avise que vai confirmar com a equipe e não ofereça horário.')
  rescue StandardError => e
    Rails.logger.error("[Athenas calendar] tool=#{name} #{e.class}: #{e.message}")
    error('Não consegui falar com a agenda agora.')
  end

  private

  def dispatch(name, input)
    case name
    when 'consultar_horarios' then check(input)
    when 'agendar' then book(input)
    when 'meus_agendamentos' then mine
    when 'remarcar' then reschedule(input)
    when 'desmarcar' then cancel(input)
    else error("Ferramenta #{name} não existe.")
    end
  end

  def check(input)
    services = resolve_services(input[:servicos])
    return unknown_service if services.empty?

    block = combined(services)
    slots = Ai::Calendar::AvailabilityService.new(
      assistant: @assistant, service: block, from: day_start(input[:data]), to: day_end(input[:data])
    ).perform
    { horarios: slots.first(MAX_LISTED_SLOTS).map { |slot| local(slot) },
      duracao_minutos: block.occupied_minutes }.to_json
  end

  def book(input)
    services = resolve_services(input[:servicos])
    return unknown_service if services.empty?

    appointment = Ai::Calendar::BookService.new(
      assistant: @assistant, contact: @contact, services: services,
      starts_at: parse_time(input[:inicio]), conversation: @conversation
    ).perform
    { agendado: true, id: appointment.id, inicio: local(appointment.starts_at) }.to_json
  rescue Ai::Calendar::BookService::Unavailable
    error('Esse horário acabou de ser ocupado. Consulte de novo e ofereça outro.')
  end

  def mine
    rows = Ai::Calendar::Appointment.reachable_by(@assistant, @contact).map do |appointment|
      { id: appointment.id, inicio: local(appointment.starts_at), servicos: appointment.services.map(&:name) }
    end
    { agendamentos: rows }.to_json
  end

  def reschedule(input)
    appointment = reachable(input[:agendamento_id])
    return not_found if appointment.nil?

    moved = Ai::Calendar::ChangeService.new(appointment: appointment).reschedule(parse_time(input[:novo_inicio]))
    { remarcado: true, inicio: local(moved.starts_at) }.to_json
  rescue Ai::Calendar::ChangeService::TooLate
    too_late
  rescue Ai::Calendar::ChangeService::Unavailable
    error('Esse horário não está livre. Consulte os horários e ofereça outro.')
  end

  def cancel(input)
    appointment = reachable(input[:agendamento_id])
    return not_found if appointment.nil?

    Ai::Calendar::ChangeService.new(appointment: appointment).cancel
    { desmarcado: true }.to_json
  rescue Ai::Calendar::ChangeService::TooLate
    too_late
  end

  # The operator's rule, phrased for the model so it hands over instead of
  # arguing with the customer about it.
  def too_late
    error('Está perto demais do horário para mexer sozinho. Explique isso e diga que a equipe vai confirmar.')
  end

  def unknown_service
    error('Não reconheci esse serviço. Confirme o nome com o cliente.')
  end

  def not_found
    error('Não encontrei esse agendamento.')
  end

  def reachable(id)
    Ai::Calendar::Appointment.reachable_by(@assistant, @contact).find_by(id: id)
  end

  # Accent and case insensitive, because the customer says "progressiva" and the
  # operator typed "Progressiva sem formol".
  def resolve_services(names)
    wanted = Array(names).map { |name| normalize(name) }.reject(&:blank?)
    return [] if wanted.empty?

    @assistant.calendar_services.active.select do |service|
      wanted.any? { |name| normalize(service.name).include?(name) }
    end
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip
  end

  # Several services are ONE block with the durations summed and the buffer
  # applied once, because the room is turned around after the last one and not
  # between each.
  def combined(services)
    return services.first if services.one?

    Ai::Calendar::Service.new(
      name: services.map(&:name).join(' + '),
      duration_minutes: services.sum(&:duration_minutes),
      buffer_minutes: services.map { |service| service.buffer_minutes.to_i }.max
    )
  end

  def zone
    @zone ||= ActiveSupport::TimeZone[professional&.timezone.to_s] || Time.zone
  end

  def professional
    @professional ||= @assistant.calendar_professionals.active.first
  end

  def day_start(value)
    parsed = parse_date(value)
    parsed && zone.local(parsed.year, parsed.month, parsed.day, 0, 0)
  end

  def day_end(value)
    start = day_start(value)
    start && (start + 1.day)
  end

  def parse_time(value)
    zone.parse(value.to_s) || raise(ArgumentError, "horário inválido: #{value}")
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue Date::Error
    nil
  end

  def local(time)
    time.in_time_zone(zone).strftime('%Y-%m-%dT%H:%M')
  end

  def error(message)
    { error: true, message: message }.to_json
  end
end
