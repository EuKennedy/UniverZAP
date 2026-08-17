# The Anthropic tool schemas for the belezaki agenda. Execution lives in
# Ai::Belezaki::SchedulingTools, same split as the Google calendar module.
#
# Names are in Portuguese because the conversations are, and a model reaching for
# `consultar_horarios` mid-sentence in pt-BR picks it more reliably than one
# reaching for `check_availability`.
class Ai::Belezaki::ToolDefinitions
  def self.all(include_booking:)
    defs = [services_tool, professionals_tool, availability_tool, month_tool, appointments_tool, phone_tool]
    defs += [booking_tool, comanda_tool, reschedule_tool, cancel_tool] if include_booking
    defs
  end

  # O passo que faltava no treinamento: pedir o WhatsApp e REGISTRAR.
  #
  # No WhatsApp o contato já chega com número, então isto quase nunca aparece.
  # Ele existe para o resto: widget do site, contato importado, e o playground,
  # onde a falta do número fez o modelo preencher o campo sozinho com três
  # números inventados na mesma conversa. Ver Ai::Belezaki::CustomerPhone.
  #
  # A ferramenta recusa número que não apareceu numa mensagem do cliente, então
  # não adianta o modelo chutar: ele precisa ter perguntado de verdade.
  def self.phone_tool
    tool(
      'registrar_telefone',
      'Registra o WhatsApp do cliente na ficha dele. Chame assim que ele DIGITAR o número na conversa. ' \
      'Sem isso não dá para consultar agenda, agendar, remarcar, desmarcar nem abrir comanda. ' \
      'Se você ainda não tem o número, PERGUNTE primeiro: peça o WhatsApp com DDD e espere a resposta. ' \
      'Nunca invente, nunca complete e nunca reaproveite um número de outra conversa.',
      { numero: str('exatamente como o cliente digitou, ex 31 98765-4321') },
      %w[numero]
    )
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
      'Horários livres de um serviço num dia específico. Use antes de agendar. ' \
      'A resposta já traz SÓ o que está livre: se vier vazio, não existe vaga nesse dia.',
      # O modelo mandou "manicure_pedicure", "manicure,pedicure" e "manicure"
      # quatro vezes numa conversa só, e cada uma voltou como erro de validação.
      # A descrição agora diz o que o campo é, e não só o que ele significa.
      { service_id: str('o UUID do serviço, copiado de listar_servicos, nunca o nome'),
        date: str('dia YYYY-MM-DD'),
        professional_id: str('opcional, o UUID vindo de listar_profissionais, nunca o nome') },
      %w[service_id date]
    )
  end

  def self.month_tool
    tool(
      'sugerir_dias',
      'Dias com vaga de um serviço num mês (quando o cliente não deu uma data). ' \
      'Devolve days_with_slots, a lista dos dias que têm alguma vaga.',
      { service_id: str('o UUID do serviço, copiado de listar_servicos, nunca o nome'),
        month: str('mês YYYY-MM'),
        professional_id: str('opcional, o UUID vindo de listar_profissionais, nunca o nome') },
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
      'Copie start e professional_id EXATAMENTE do slot escolhido em consultar_horarios, sem reformatar. ' \
      'Depois de agendar, diga ao cliente o horário que VOLTOU no campo inicio, não o que você tinha em mente. ' \
      'O salão manda a confirmação por WhatsApp sozinho, então não prometa mandar nada você.',
      {
        service_id: str('id do serviço, o UUID vindo de listar_servicos'),
        start: str('cópia literal do campo start do slot escolhido'),
        professional_id: str('id do profissional do MESMO slot'),
        client_name: str('nome do cliente')
      },
      %w[service_id start professional_id client_name]
    )
  end

  # Separate from `agendar` on purpose, and the prompt spells out the order:
  # reserve the chair, say the price out loud, offer only the methods the salon
  # takes, wait for a yes, THEN open. A comanda opened for someone who never
  # agreed is a phantom line in the salon's takings.
  def self.comanda_tool
    tool(
      'abrir_comanda',
      'Abre a comanda (registro de faturamento) de um agendamento. SÓ chame depois de dizer o valor ao ' \
      'cliente e ele confirmar que aceita, e depois de ele escolher a forma de pagamento. Nunca chame por ' \
      'conta própria logo após agendar.',
      { appointment_id: str('id devolvido por agendar ou por meus_agendamentos'),
        forma_pagamento: str('PIX, CREDIT, DEBIT, CASH ou PACKAGE — só as que o salão aceita') },
      %w[appointment_id forma_pagamento]
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
