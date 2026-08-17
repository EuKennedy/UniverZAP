# O agente disse que agendou, e nada foi agendado.
#
# "Prontinho, agendei sua escova", "já deixei reservado", "fica marcado então":
# a frase encerra a conversa, a pessoa guarda o celular achando que tem horário,
# e aparece num dia em que ninguém a espera. É a promessa que o agente não tem
# como cumprir sozinho, porque cumpri-la exigia uma escrita numa agenda que não
# aconteceu.
#
# O sinal já está gravado, e o nome da bandeira é o que ela mede de verdade:
# `promessa_solta` é escrito por Ai::Guardrails::ResponseAudit quando o texto
# afirma ter agendado, reservado, marcado, separado, confirmado, garantido ou
# bloqueado E nenhuma escrita externa aconteceu naquele turno. Reavaliar aqui
# produziria uma opinião pior: o guardrail sabia se a ferramenta rodou, e o log
# não guarda isso.
class Ai::Manager::Checks::LoosePromise < Ai::Manager::Checks::Base
  FLAG = 'promessa_solta'.freeze

  # Teto de linhas lidas por rodada, igual às outras verificações: o cruzamento
  # final com a agenda é em Ruby, e a varredura de uma conta grande precisa
  # custar o mesmo que a de uma pequena. Cortar por cima só faz a verificação
  # falar menos, nunca mais.
  MAX_ROWS = 500

  # Os dois juntos, e não um ou outro. Só a taxa transformaria 2 respostas de um
  # agente novo em "40% das mensagens"; só a contagem absoluta encheria a fila do
  # agente movimentado que erra 4 vezes em 900. O par é o que faz a verificação
  # falar quando é padrão e calar quando é escorregão.
  MIN_OCCURRENCES = 3
  MIN_RATE = 5.0

  def self.key
    'loose_promise'
  end

  def self.title
    'Confirmação de agendamento que a agenda nunca recebeu'
  end

  def self.what_it_measures
    'Respostas que afirmam ter agendado ou reservado sem que nada tenha sido escrito na agenda.'
  end

  def self.severity
    'high'
  end

  def self.target
    'prompt_version'
  end

  def run
    total = scope.messages_count
    return [] if total.zero?

    occurrences = unbacked_messages.length
    percentage = rate(occurrences, total)
    return [] if occurrences < MIN_OCCURRENCES || percentage < MIN_RATE

    [build_finding(occurrences, total, percentage)]
  end

  private

  # `auto_flags` e não `auto_flag`: a coluna singular guarda só a bandeira de
  # maior severidade, então uma resposta que também inventou preço esconderia a
  # promessa solta atrás dele.
  def flagged
    @flagged ||= scope.replies.where('auto_flags @> ?', [FLAG].to_json)
  end

  # As afirmações que a agenda NÃO confirma, contadas por mensagem entregue.
  #
  # O guardrail marca a resposta quando o texto diz "agendei" e nenhuma escrita
  # aconteceu naquele turno, o que também marca a resposta legítima que apenas
  # relembra um horário marcado ontem ("sim, está marcado para sexta às 14h").
  # Numa operação onde o cliente confere o horário antes de sair de casa, essa
  # classe sozinha encheria a fila, e a sugestão que sairia dela ensinaria o
  # agente a não confirmar o que existe. Cruzar com a agenda tira a classe
  # inteira: se a conversa tem agendamento, o agente estava contando a verdade.
  #
  # O resíduo conhecido é o salão que agenda no belezaki, cujo livro não escreve
  # linha em ai_calendar_appointments. Ali a verificação continua tão cega quanto
  # o guardrail, e não mais.
  def unbacked_messages
    @unbacked_messages ||= flagged.order(created_at: :desc).limit(MAX_ROWS)
                                  .pluck(:conversation_id, :message_id)
                                  # rubocop:disable Style/HashExcept
                                  # O cop enxerga um Hash aqui e sugere `except`, mas `pluck` com
                                  # duas colunas devolve array de pares: aceitar o autocorrect
                                  # troca este reject por um NoMethodError em produção.
                                  .reject { |conversation_id, _| booked_conversations.include?(conversation_id) }
                                  # rubocop:enable Style/HashExcept
                                  .map(&:last).uniq
  end

  def booked_conversations
    @booked_conversations ||= scope.appointments.booked.where.not(conversation_id: nil)
                                   .distinct.pluck(:conversation_id).to_set
  end

  def build_finding(occurrences, total, percentage)
    sample = flagged.where(message_id: unbacked_messages).where.not(ai_response: [nil, ''])
                    .order(created_at: :desc).pick(:conversation_id, :ai_response)
    finding(
      title: 'O agente confirmou um agendamento que não foi feito',
      rationale: rationale_for(occurrences, total),
      evidence: evidence(
        conversation_id: sample&.first,
        # A regex é a mesma que levantou a bandeira, então o trecho mostrado é
        # literalmente a frase pela qual a resposta foi marcada.
        excerpt: sentence_containing(sample&.last, Ai::Guardrails::ResponseAudit::LOOSE_PROMISE),
        metric: 'porcentagem_das_respostas', value: percentage
      ),
      proposed: { 'instruction' => DIRECTIVE }
    )
  end

  def rationale_for(occurrences, total)
    "#{occurrences} de #{total} respostas entregues no período afirmaram ter agendado, reservado ou marcado " \
      'sem que nenhuma linha tenha sido escrita na agenda naquele momento, e sem que a conversa tivesse ' \
      'agendamento nenhum. Cada uma dessas é uma pessoa que guardou o celular achando que tem horário e vai ' \
      'aparecer num dia em que ninguém a espera, e quem explica isso é a pessoa no balcão. ' \
      'A correção é de instrução: confirmar só depois que a ferramenta de agenda responder.'
  end

  DIRECTIVE = <<~RULE.strip.freeze
    📌 SÓ CONFIRME O QUE A FERRAMENTA JÁ FEZ:
    • PROIBIDO escrever "agendei", "marquei", "reservei", "deixei separado",
      "fica reservado" ou "está confirmado" antes de a ferramenta de agenda
      responder com o agendamento criado. Sem essa resposta, nada foi agendado,
      e a frase vira uma pessoa chegando num dia em que ninguém a espera.
    • Precisa agendar? Use a ferramenta AGORA e escreva a confirmação depois que
      ela voltar, repetindo o horário que ela devolveu.
    • Faltou alguma informação para agendar? Diga exatamente o que falta e faça a
      pergunta que resolve, na mesma mensagem. Uma pergunta mantém a conversa
      viva; uma confirmação falsa a encerra com o cliente enganado.
  RULE
end
