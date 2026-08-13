# The Anthropic tool schemas for the belezaki agenda. Execution lives in
# Ai::Belezaki::SchedulingTools, same split as the Google calendar module.
#
# Names are in Portuguese because the conversations are, and a model reaching for
# `consultar_horarios` mid-sentence in pt-BR picks it more reliably than one
# reaching for `check_availability`.
class Ai::Belezaki::ToolDefinitions
  def self.all(include_booking:)
    defs = [services_tool, professionals_tool, availability_tool, month_tool, appointments_tool]
    defs += [booking_tool, reschedule_tool, cancel_tool] if include_booking
    defs
  end

  def self.services_tool
    tool('listar_servicos', 'Lista os serviços agendáveis do salão (id, nome, duração, preço, profissionais).')
  end

  def self.professionals_tool
    tool('listar_profissionais', 'Lista os profissionais do salão e os serviços que cada um faz.')
  end

  def self.availability_tool
    tool(
      'consultar_horarios',
      'Horários livres de um serviço num dia específico. Use antes de agendar.',
      { service_id: str('id do serviço'), date: str('dia YYYY-MM-DD'), professional_id: str('opcional') },
      %w[service_id date]
    )
  end

  def self.month_tool
    tool(
      'sugerir_dias',
      'Dias com vaga de um serviço num mês (quando o cliente não deu uma data).',
      { service_id: str('id do serviço'), month: str('mês YYYY-MM'), professional_id: str('opcional') },
      %w[service_id month]
    )
  end

  # No phone parameter, deliberately: the number comes from the Contact record,
  # never from what the model read in the chat. The phone IS the scope on the
  # salon side, so a mistyped digit would hand this customer somebody else's
  # appointments.
  def self.appointments_tool
    tool(
      'meus_agendamentos',
      'Agendamentos deste cliente. Use SEMPRE antes de remarcar ou desmarcar, para achar o id e confirmar com ' \
      'ele QUAL agendamento. Respeite can_cancel e can_reschedule: se vierem falsos, encaminhe para a equipe.'
    )
  end

  # `professional_id` is required HERE even though the API allows omitting it.
  # Omitted, the salon opens a separate transaction just to pick somebody — a
  # second race window — and its auto-choice can land on a professional the book
  # itself then rejects with a 400, after the customer was already offered the
  # time. Every slot already carries the id; copying it removes both problems.
  def self.booking_tool
    tool(
      'agendar',
      'Cria o agendamento na agenda do salão. SÓ chame depois de confirmar nome e horário com o cliente. ' \
      'Copie start e professional_id EXATAMENTE do slot escolhido em consultar_horarios, sem reformatar.',
      {
        service_id: str('id do serviço'),
        start: str('cópia literal do campo start do slot escolhido'),
        professional_id: str('id do profissional do MESMO slot'),
        client_name: str('nome do cliente'),
        client_phone: str('telefone E.164, ex +5531999999999')
      },
      %w[service_id start professional_id client_name client_phone]
    )
  end

  def self.reschedule_tool
    tool(
      'remarcar',
      'Move um agendamento deste cliente para outro horário. Só chame depois de ele confirmar o novo horário. ' \
      'O start precisa ser copiado literalmente de consultar_horarios.',
      { appointment_id: str('id vindo de meus_agendamentos'),
        start: str('cópia literal do campo start do slot escolhido'),
        professional_id: str('opcional, só se o cliente quiser trocar de profissional') },
      %w[appointment_id start]
    )
  end

  def self.cancel_tool
    tool(
      'desmarcar',
      'Cancela um agendamento deste cliente. Só chame depois de ele confirmar explicitamente que quer cancelar. ' \
      'Libera o horário e avisa a lista de espera do salão.',
      { appointment_id: str('id vindo de meus_agendamentos'),
        reason: str('opcional, o motivo em poucas palavras') },
      %w[appointment_id]
    )
  end

  def self.tool(name, description, properties = {}, required = [])
    { name: name, description: description, input_schema: { type: 'object', properties: properties, required: required } }
  end

  def self.str(description)
    { type: 'string', description: description }
  end
end
