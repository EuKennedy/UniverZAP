# Anthropic tool-use definitions + executor for belezaki scheduling.
#
# `.definitions` returns the tool schemas exposed to Claude (read tools always;
# the `agendar` write tool only when booking is allowed). An instance executes
# a tool call by name against the belezaki AgentClient and returns a JSON string
# (the tool_result content fed back to Claude).
class Ai::Belezaki::SchedulingTools
  def self.definitions(include_booking:)
    defs = [
      tool('listar_servicos', 'Lista os serviços agendáveis do salão (id, nome, duração, preço, profissionais).'),
      tool('listar_profissionais', 'Lista os profissionais do salão e os serviços que cada um faz.'),
      tool(
        'consultar_horarios',
        'Horários livres de um serviço num dia específico. Use antes de agendar.',
        { service_id: str('id do serviço'), date: str('dia YYYY-MM-DD'), professional_id: str('opcional') },
        %w[service_id date]
      ),
      tool(
        'sugerir_dias',
        'Dias com vaga de um serviço num mês (quando o cliente não deu uma data).',
        { service_id: str('id do serviço'), month: str('mês YYYY-MM'), professional_id: str('opcional') },
        %w[service_id month]
      )
    ]
    defs << booking_tool if include_booking
    defs
  end

  def self.booking_tool
    tool(
      'agendar',
      'Cria o agendamento na agenda do salão. SÓ chame depois de confirmar nome e horário com o cliente.',
      {
        service_id: str('id do serviço'),
        start: str('início ISO 8601 com offset, ex 2026-06-20T16:00:00-03:00'),
        professional_id: str('opcional — se vazio o salão escolhe um livre'),
        client_name: str('nome do cliente'),
        client_phone: str('telefone E.164, ex +5531999999999')
      },
      %w[service_id start client_name client_phone]
    )
  end

  def self.tool(name, description, properties = {}, required = [])
    { name: name, description: description, input_schema: { type: 'object', properties: properties, required: required } }
  end

  def self.str(description)
    { type: 'string', description: description }
  end

  def initialize(client, scope:)
    @client = client
    # Namespace for booking idempotency keys — keeps this conversation's
    # bookings from ever colliding with another conversation's on belezaki.
    @scope = scope
  end

  # Returns a JSON string for the tool_result. Never raises — belezaki errors
  # are returned as data so Claude can apologise/redirect gracefully.
  def call(name, input)
    input ||= {}
    result = dispatch(name, input)
    result.is_a?(String) ? result : result.to_json
  rescue Ai::Belezaki::AgentClient::Error => e
    { error: 'belezaki_error', message: e.message }.to_json
  rescue StandardError => e
    # Never crash the tool loop / autopilot job — hand the error back to Claude
    # as data so it can apologise and continue.
    Rails.logger.error("[Athenas agent] tool #{name} failed: #{e.class}: #{e.message}")
    { error: 'tool_error', message: 'Não consegui completar essa ação agora.' }.to_json
  end

  private

  def dispatch(name, input)
    case name
    when 'listar_servicos' then @client.services
    when 'listar_profissionais' then @client.professionals
    when 'consultar_horarios'
      @client.availability(service_id: input['service_id'], date: input['date'], professional_id: input['professional_id'])
    when 'sugerir_dias'
      @client.availability_month(service_id: input['service_id'], month: input['month'], professional_id: input['professional_id'])
    when 'agendar' then book(input)
    else { error: 'unknown_tool', message: "Ferramenta #{name} não existe." }
    end
  end

  def book(input)
    @client.create_appointment(
      service_id: input['service_id'],
      start: input['start'],
      professional_id: input['professional_id'],
      client: { name: input['client_name'], phone: input['client_phone'] },
      source: 'whatsapp_agent',
      idempotency_key: booking_idempotency_key(input)
    )
  end

  # Idempotency must key on the ACTION (this specific appointment), not on the
  # conversation tick. Hashing service + start + professional + phone means:
  #   - a re-book of the SAME slot (client confirms again in a later turn)
  #     yields the SAME key, so belezaki dedups it (no duplicate booking);
  #   - two DIFFERENT bookings in the same turn ("corte terca e escova quinta")
  #     get DIFFERENT keys, so both go through.
  # The old "conv-<id>-<maxmsgid>" key did the opposite on both counts.
  def booking_idempotency_key(input)
    action = [input['service_id'], input['start'], input['professional_id'], input['client_phone']].join('|')
    "#{@scope}:#{Digest::SHA256.hexdigest(action)[0, 24]}"
  end
end
