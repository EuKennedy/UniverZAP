# The Anthropic tool schemas for the agenda.
#
# Built from the agent's OWN services, so the model is told the exact names the
# operator typed instead of guessing them, and returns nil when there is
# nothing to book with: a model holding a booking tool it cannot fulfil will
# promise a time anyway.
class Ai::Calendar::ToolDefinitions
  def self.for(assistant)
    services = assistant.calendar_services.active.to_a
    return nil if assistant.calendar_professionals.active.none? || services.empty?

    new(services.map(&:name).join(', ')).all
  end

  def initialize(menu)
    @menu = menu
  end

  def all
    [check, book, list, reschedule, cancel]
  end

  private

  def check
    tool('consultar_horarios',
         'Horários REAIS livres na agenda. Use SEMPRE antes de oferecer qualquer horário. Nunca invente ' \
         'horário e nunca diga que vai verificar sem chamar esta ferramenta.',
         { servicos: array_of("nomes exatos, dentre: #{@menu}"),
           data: str('opcional, dia desejado no formato AAAA-MM-DD') },
         ['servicos'])
  end

  def book
    tool('agendar',
         'Marca o horário na agenda. Só chame depois de consultar_horarios e com o cliente confirmando um ' \
         'horário que apareceu na lista.',
         { servicos: array_of("nomes exatos, dentre: #{@menu}"),
           inicio: str('início escolhido, formato AAAA-MM-DDTHH:MM') },
         %w[servicos inicio])
  end

  def list
    tool('meus_agendamentos', 'Agendamentos futuros deste cliente. Use antes de remarcar ou desmarcar.')
  end

  def reschedule
    tool('remarcar', 'Move um agendamento existente deste cliente para outro horário já confirmado como livre.',
         { agendamento_id: str('id vindo de meus_agendamentos'),
           novo_inicio: str('novo início, formato AAAA-MM-DDTHH:MM') },
         %w[agendamento_id novo_inicio])
  end

  def cancel
    tool('desmarcar', 'Cancela um agendamento existente deste cliente.',
         { agendamento_id: str('id vindo de meus_agendamentos') }, ['agendamento_id'])
  end

  def tool(name, description, properties = {}, required = [])
    { name: name, description: description,
      input_schema: { type: 'object', properties: properties, required: required } }
  end

  def str(description)
    { type: 'string', description: description }
  end

  def array_of(description)
    { type: 'array', description: description, items: { type: 'string' } }
  end
end
