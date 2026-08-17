# O agente marcou um horário e contou outro para o cliente.
#
# Falha real, vista no log: a ferramenta recebeu 13:00, devolveu inicio=13:00, e
# a confirmação saiu "pronto, te espero às 14h". O cliente anota 14h, chega às
# 14h, e a cadeira estava reservada à 13h. É a pior coisa que este módulo
# consegue fazer depois de confirmar um agendamento que não existe, e por isso é
# crítica: não existe amostra mínima aqui, uma ocorrência já é o bastante.
#
# A comparação é contra `ai_calendar_appointments`, que é o nosso índice do que
# NÓS agendamos. O resultado da ferramenta não é persistido em lugar nenhum
# (Ai::Agent::ToolLoopService o carrega em memória e o descarta no fim do turno),
# e a linha da agenda é exatamente o mesmo fato tornado durável: o horário que
# de fato ficou escrito.
class Ai::Manager::Checks::PromisedTimeMismatch < Ai::Manager::Checks::Base
  # Quanto tempo depois da linha da agenda a confirmação ainda é do mesmo turno.
  # Passou disso, a resposta é sobre outra coisa e comparar seria inventar.
  CONFIRMATION_WINDOW = 10.minutes

  # Teto de agendamentos lidos numa rodada. Uma auditoria semanal não é um
  # relatório histórico, e um teto é o que garante que a varredura de uma conta
  # grande continue custando o mesmo que a de uma pequena.
  MAX_APPOINTMENTS = 500

  # "14h", "14 horas", "14:30", "14h30", sempre com a preposição na frente: o
  # horário APRESENTADO como horário. O minuto é opcional de propósito, porque é
  # assim que se fala hora no Brasil e exigi-lo faria a verificação ignorar
  # justamente a frase da falha real.
  #
  # A preposição é o que separa "te espero às 14h" de "a progressiva leva 3h".
  # As duas são "3h" para uma regex, e sem ela uma confirmação que só menciona a
  # duração do serviço viraria divergência crítica.
  #
  # `(?<![[:alnum:]])` e NÃO `\b` na frente: o `\b` do Ruby é ASCII, e "à" não é
  # letra para ele. Um `\b[àa]s` não casa " às 14h", casa só a forma sem acento,
  # e a verificação inteira ficaria muda em produção sobre a única frase que ela
  # existe para pegar. A classe POSIX é unicode e resolve nos dois sentidos.
  PROMISED_TIME = /(?<![[:alnum:]])(?:[àa]s|pr[ao]s?|para(?:\s+as)?)\s+(\d{1,2})\s*(?:h(?:oras?)?|:)\s*(\d{2})?\b/i

  # O que, numa confirmação, NÃO é o horário deste cliente: o funcionamento da
  # casa, um prazo para avisar, uma faixa de movimento. Sai da frase antes da
  # leitura.
  #
  # A preposição sozinha não bastava, e é aqui que estava o buraco: "prontinho,
  # agendado! a gente fecha às 19h" tem uma hora apresentada como horário que
  # não é promessa nenhuma, e a verificação a acusaria como divergência crítica.
  # Metade das confirmações de salão fecha assim (horário de funcionamento,
  # prazo para remarcar, faixa de menos movimento), e como esta verificação é
  # crítica e dispara com uma ocorrência só, bastava uma dessas para o operador
  # nunca mais abrir a aba.
  #
  # Cada verbo entra inteiro e entre `\b`, nunca como prefixo: no Brasil
  # "Fechado!" quer dizer "combinado", e um `fecha\w*` calaria a confirmação mais
  # comum que existe ("Fechado! Te espero às 14h").
  NOT_A_PROMISE = /
    \bd[ao]s\s+\d{1,2}\s*(?:h(?:oras?)?|:)\s*\d{0,2}\s*(?:[àa]s|at[ée]|a)\s+\d{1,2}\s*(?:h(?:oras?)?|:)\s*\d{0,2}|
    \b(?:at[ée]|antes|depois|a\s+partir)\s+(?:d[ao]s?\s+)?[àa]?s?\s*\d{1,2}\s*(?:h(?:oras?)?|:)\s*\d{0,2}|
    \b(?:abre|abrimos|abertos?|fecha|fechamos|funcionamos|funcionamento|atendemos|atendimento)\b
    [^.!?\n]{0,30}?\d{1,2}\s*(?:h(?:oras?)?|:)\s*\d{0,2}
  /xi

  # A frase que fala DESTE agendamento, e a única que pode acusar. O preço de
  # não estar nela é o silêncio, que é o lado certo para errar: uma confirmação
  # escrita sem nenhuma destas palavras ("quinta, 14h então!") deixa de ser
  # auditada, e isso custa menos que um cartão crítico errado.
  BOOKING_SENTENCE = /
    \b(?:agend\w*|marqu\w*|marcad\w*|reserv\w*|encaix\w*|confirm\w*|combinad\w*|anot\w*|
    deixei|fica|ficou|espero|aguardo|hor[áa]rio)\b
  /xi

  def self.key
    'promised_time_mismatch'
  end

  def self.title
    'Horário prometido diferente do horário agendado'
  end

  def self.what_it_measures
    'Confirmações em que o agente escreveu um horário que não bate com o que ficou na agenda.'
  end

  def self.severity
    'critical'
  end

  def self.target
    'prompt_version'
  end

  def run
    mismatches = collect_mismatches
    return [] if mismatches.empty?

    [build_finding(mismatches)]
  end

  private

  def collect_mismatches
    appointments = booked_appointments
    return [] if appointments.empty?

    confirmations = confirmations_for(appointments)
    appointments.filter_map { |appointment| mismatch_for(appointment, confirmations[appointment.conversation_id]) }
  end

  def booked_appointments
    @booked_appointments ||= scope.appointments.booked.where.not(conversation_id: nil)
                                  .order(created_at: :desc).limit(MAX_APPOINTMENTS).to_a
  end

  # Uma consulta para todas as conversas envolvidas, e não uma por agendamento:
  # a diferença entre duas consultas por rodada e quinhentas.
  def confirmations_for(appointments)
    scope.replies.where(conversation_id: appointments.map(&:conversation_id))
         .where.not(ai_response: [nil, ''])
         .order(:created_at)
         .pluck(:conversation_id, :ai_response, :created_at)
         .group_by(&:first)
  end

  def mismatch_for(appointment, candidates)
    reply = confirmation_after(appointment, candidates)
    return nil if reply.blank?

    text = reply[1]
    # Absolver é generoso: um horário apresentado que bate com a agenda diz que o
    # cliente foi informado direito, esteja ele em que frase estiver. Silêncio
    # também não é divergência.
    return nil if absolved?(text, appointment)

    # Acusar é estrito: só o horário dito numa frase que fala DESTE agendamento.
    claimed = claimed_times(text)
    return nil if claimed.empty?

    { appointment: appointment, text: text, stated: claimed }
  end

  def absolved?(text, appointment)
    promised = promised_times(text)
    promised.empty? || promised.any? { |time| matches?(time, appointment) }
  end

  # Frase a frase, e não a mensagem inteira, para que o funcionamento da casa
  # citado numa frase não absolva nem acuse a confirmação escrita na outra.
  #
  # A absolvição passa pelo mesmo funil de propósito, e é a segunda metade do
  # conserto: quando qualquer número servia para absolver, "marquei às 14h, o
  # corte leva 1h" derrubava a divergência real de um agendamento à 13h, porque
  # "1h" bate com 13h pela regra das doze horas. Uma duração não pode nem acusar
  # nem inocentar.
  def promised_times(text)
    times_in(sentences(text))
  end

  # Só as frases que falam deste agendamento. "A Ana começa a atender às 8h" é
  # uma hora apresentada como horário e não promete nada a este cliente: sem
  # este filtro, uma frase dessas ao lado de uma confirmação correta viraria
  # divergência crítica, e crítica aqui dispara com uma ocorrência só.
  def claimed_times(text)
    times_in(sentences(text).grep(BOOKING_SENTENCE))
  end

  def times_in(list)
    list.flat_map { |sentence| stated_times(spoken(sentence)) }
  end

  def spoken(sentence)
    sentence.gsub(NOT_A_PROMISE, ' ')
  end

  # A frase que carrega a promessa, e não a primeira que tenha um número dentro:
  # é isto que o operador lê no cartão, e mostrar "a gente fecha às 19h" como
  # evidência de horário divergente queimaria a única coisa que faz a fila ser
  # lida.
  def promise_sentence(text)
    sentences(text).find { |line| line.match?(BOOKING_SENTENCE) && stated_times(spoken(line)).any? } || text
  end

  def confirmation_after(appointment, candidates)
    Array(candidates).find do |_conversation_id, _text, created_at|
      created_at.between?(appointment.created_at, appointment.created_at + CONFIRMATION_WINDOW)
    end
  end

  def stated_times(text)
    text.to_s.scan(PROMISED_TIME).map { |hour, minute| [hour.to_i, minute.to_i] }
        .select { |hour, minute| hour.between?(0, 23) && minute.between?(0, 59) }
  end

  # Hora sem minuto casa com qualquer minuto daquela hora: "te espero às 13h"
  # para um agendamento às 13:30 é imprecisão de linguagem, não o cliente indo
  # no dia errado.
  #
  # E uma hora de até 12 também casa com ela mais doze, porque "às 2h da tarde"
  # é 14:00 e recusar isso encheria a fila de divergência que não existe. O
  # preço é deixar passar um "1h" que realmente queria dizer 01:00, e esse é o
  # lado certo para errar numa verificação crítica.
  def matches?(stated, appointment)
    hour, minute = stated
    local = appointment.starts_at.in_time_zone(scope.zone)
    candidates = hour <= 12 ? [hour, hour + 12] : [hour]
    candidates.include?(local.hour) && (minute.zero? || minute == local.min)
  end

  def build_finding(mismatches)
    worst = mismatches.first
    booked_at = worst[:appointment].starts_at.in_time_zone(scope.zone).strftime('%d/%m às %H:%M')
    said = format_stated(worst[:stated].first)
    finding(
      title: 'O agente confirmou um horário diferente do que ficou agendado',
      rationale: rationale_for(mismatches.length, booked_at, said),
      evidence: evidence(
        conversation_id: worst[:appointment].conversation_id,
        excerpt: promise_sentence(worst[:text]),
        metric: 'agendamentos_com_hora_errada', value: mismatches.length
      ),
      proposed: { 'instruction' => DIRECTIVE }
    )
  end

  def format_stated(stated)
    hour, minute = stated
    format('%<hour>02d:%<minute>02d', hour: hour, minute: minute)
  end

  def rationale_for(count, booked_at, said)
    "A agenda registrou #{booked_at} e a mensagem que o cliente recebeu falava em #{said}. " \
      "Foram #{count} confirmação(ões) assim no período. O cliente anota o horário da mensagem, " \
      'não o da agenda, então cada uma dessas é uma pessoa chegando na hora errada. ' \
      'A correção é de instrução: o horário da confirmação tem que ser cópia literal do que a ferramenta devolveu.'
  end

  DIRECTIVE = <<~RULE.strip.freeze
    ⏰ HORÁRIO CONFIRMADO É CÓPIA, NÃO RESUMO:
    • Ao confirmar agendamento, escreva o horário EXATAMENTE como a ferramenta
      devolveu no campo de início. Se voltou 13:00, a mensagem diz 13:00.
    • PROIBIDO arredondar, converter, somar a duração ou "ajustar" o horário na
      hora de escrever. Não existe horário aproximado numa confirmação.
    • Se a ferramenta não devolveu horário, não confirme: pergunte de novo.
  RULE
end
