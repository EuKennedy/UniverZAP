# O que o modelo mandou, conferido antes de virar chamada ao salão.
#
# Cada regra aqui nasceu de um erro observado num rastro de conversa real, e
# não de imaginação sobre o que poderia dar errado. Vale registrar, porque a
# tentação de "simplificar" essas checagens volta sempre:
#
#   * data que não existe: `2026-02-30` responde 200 com os horários reais de
#     2 de março, sob um envelope que diz 30 de fevereiro. O agente ofereceria
#     um dia inexistente e o cliente aceitaria.
#   * id que é nome: o modelo mandou `manicure_pedicure`, `manicure,pedicure` e
#     `manicure` quatro vezes na mesma conversa. O comentário antigo dizia para
#     não validar formato porque "um id alucinado teria o formato de um id
#     real". Não tem.
#   * escrita sem telefone: ver Ai::Belezaki::CustomerPhone para o agendamento
#     duplicado e a confirmação que morreu em silêncio.
#
# A recusa nomeia a CORREÇÃO e não o erro. O conselho genérico do salão para
# validação mandava oferecer outro horário, o que para um id errado não conserta
# nada e faz o agente girar em falso oferecendo vagas que não vai conseguir
# marcar.
class Ai::Belezaki::InputGuard
  UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  # Campos que o salão exige como UUID, por ferramenta.
  ID_FIELDS = {
    'consultar_horarios' => %w[service_id professional_id],
    'sugerir_dias' => %w[service_id professional_id],
    'agendar' => %w[service_id professional_id],
    'remarcar' => %w[appointment_id professional_id],
    'desmarcar' => %w[appointment_id],
    'abrir_comanda' => %w[appointment_id]
  }.freeze

  # Tudo que fala do cliente com o salão precisa do WhatsApp DELE: a agenda
  # grava por telefone, `meus_agendamentos` escopa por telefone, e a confirmação
  # automática resolve o número no WhatsApp antes de enviar. Sem número certo os
  # três falham, e dois deles falham calados.
  PHONE_REQUIRED = %w[agendar abrir_comanda remarcar desmarcar meus_agendamentos].freeze

  def self.refuse(message)
    { error: 'invalid_input', message: message }
  end

  def initialize(phone)
    @phone = phone
  end

  # A recusa, ou nil quando está tudo em ordem.
  def problem(name, input)
    time_problem(name, input) || id_problem(name, input) || phone_problem(name)
  end

  private

  def refuse(message)
    self.class.refuse(message)
  end

  def time_problem(name, input)
    case name
    when 'consultar_horarios'
      refuse('Data inválida. Use AAAA-MM-DD com um dia que exista.') unless real_date?(input['date'])
    when 'sugerir_dias'
      refuse('Mês inválido. Use AAAA-MM.') unless real_month?(input['month'])
    when 'agendar', 'remarcar'
      refuse('Horário inválido. Copie o campo start do slot escolhido.') unless parsable_time?(input['start'])
    end
  end

  def id_problem(name, input)
    bad = Array(ID_FIELDS[name]).find do |field|
      input[field].present? && !input[field].to_s.match?(UUID_FORMAT)
    end
    return nil if bad.nil?

    refuse("O campo #{bad} precisa ser o id exato devolvido pela ferramenta, e não o nome do serviço ou da " \
           'pessoa. Chame listar_servicos ou consultar_horarios e copie o id de lá.')
  end

  def phone_problem(name)
    return nil unless PHONE_REQUIRED.include?(name)
    return nil if @phone.present?

    refuse('Ainda não tenho o WhatsApp deste cliente. Peça o número com DDD, e quando ele responder chame ' \
           'registrar_telefone com o que ele digitou. Só depois disso dá para mexer na agenda.')
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
end
