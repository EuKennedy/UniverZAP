# A camada que não custa nada: tudo que dá para concluir de uma consulta.
#
# Existe para que a leitura por modelo receba dezenas de conversas em vez de
# centenas. Numa conta com 200 conversas em 24h, esta classe varre as 200 de
# graça, resolve sozinha os casos que são contagem ("a última mensagem é do
# cliente e ninguém respondeu"), e entrega ao leitor só o que sobrou. É o que
# torna a janela de 30 dias tão barata quanto a de um dia, e é por isso que a
# ordem importa: triagem primeiro, modelo depois, nunca o contrário.
#
# Nada aqui é opinião. Todo achado desta classe é verificável relendo o banco,
# e é isso que permite mostrá-los sem ressalva enquanto os do leitor levam a
# etiqueta de que foram interpretados.
class Ai::Manager::Conversations::Triage
  Cases = Ai::Manager::Conversations::Cases

  # O piso para MANDAR LER é mais baixo que o piso para ACUSAR. Uma conversa
  # parada há duas horas ainda não é um cartão de "cliente esperando", mas já
  # pode ser uma compra travada, e é justamente esse caso que o operador quer
  # pegar enquanto ainda dá para salvar.
  READ_WAIT_FLOOR_HOURS = 2
  # Conversa com ida e volta de verdade. Abaixo disso não há diálogo para
  # interpretar, e mandar ler duas mensagens é pagar por um palpite.
  READ_MIN_MESSAGES = 4

  # O que cada bandeira do guardrail significa em português, para o cartão dizer
  # o que aconteceu em vez de mostrar o nome interno da coluna.
  FLAG_PHRASES = {
    'preco_inventado' => 'citou um preço que não saiu da base de conhecimento',
    'horario_divergente' => 'confirmou um horário diferente do que ficou agendado',
    'promessa_solta' => 'afirmou ter agendado sem que nada tivesse sido agendado',
    'sem_fonte' => 'afirmou um fato sem lastro em nenhuma fonte',
    'baixa_confianca' => 'respondeu sem confiança no que estava dizendo'
  }.freeze

  def initialize(account:, since:, now: Time.current)
    @account = account
    @since = since
    @now = now
  end

  def findings
    @findings ||= (waiting_findings + repeated_findings + flagged_findings).compact
  end

  # As conversas que valem a leitura por modelo, da mais urgente para a menos.
  # Ordenadas pelo tempo de espera porque é o que decide quem some primeiro.
  def candidates
    @candidates ||= activity.rows.values
                            .select { |row| worth_reading?(row) }
                            .sort_by { |row| -row.waited_hours(@now) }
                            .map(&:conversation_id)
                            .select { |id| details.for(id) }
  end

  def scanned
    activity.rows.size
  end

  def capped?
    activity.capped?
  end

  # Público porque o leitor reusa o mesmo carregamento. Instanciar Details de
  # novo lá dentro repetiria seis consultas por causa de um objeto pronto.
  def details
    @details ||= Ai::Manager::Conversations::Details.new(
      account: @account,
      conversation_ids: activity.rows.keys | signals.repeated.keys | signals.flagged.keys
    )
  end

  # conversation_id => horas de espera, para o leitor dizer ao modelo há quanto
  # tempo aquela pessoa está parada sem precisar deduzir do relógio.
  def waits
    @waits ||= activity.rows.transform_values { |row| row.waited_hours(@now) }
  end

  private

  def worth_reading?(row)
    row.waited_hours(@now) >= READ_WAIT_FLOOR_HOURS || row.messages >= READ_MIN_MESSAGES
  end

  def activity
    @activity ||= Ai::Manager::Conversations::Activity.new(account: @account, since: @since)
  end

  def signals
    @signals ||= Ai::Manager::Conversations::AgentSignals.new(account: @account, since: @since)
  end

  # Conversa resolvida ou adiada não entra: o silêncio ali foi uma decisão de
  # alguém, e acusá-lo transforma o painel numa lista de coisas que o operador
  # já resolveu.
  OPEN_STATES = %w[open pending].freeze

  def waiting_findings
    activity.rows.values.filter_map do |row|
      hours = row.waited_hours(@now)
      next if hours < Cases::WAIT_FLOOR_HOURS

      detail = details.for(row.conversation_id)
      next if detail.nil? || OPEN_STATES.exclude?(detail.status)

      waiting_finding(detail, row, hours)
    end
  end

  def waiting_finding(detail, row, hours)
    build(detail, 'cliente_esperando',
          severity: Cases.severity_by_wait(hours),
          detail: "#{who(detail)} escreveu #{humanized(hours)} e ninguém respondeu depois disso.",
          excerpt: detail.excerpt, occurred_at: row.last_in, waiting_since: row.last_in,
          metadata: { 'waited_hours' => hours })
  end

  def repeated_findings
    signals.repeated.filter_map do |conversation_id, signal|
      detail = details.for(conversation_id)
      next if detail.nil?

      build(detail, 'agente_repetiu',
            detail: "O agente entregou a mesma resposta #{signal[:count]} vezes nesta conversa, " \
                    'sinal de que travou em vez de avançar.',
            excerpt: signal[:excerpt], occurred_at: last_activity(conversation_id),
            metadata: { 'repeats' => signal[:count] })
    end
  end

  # A bandeira `cliente_insatisfeito` fala do CLIENTE e as outras falam do que o
  # agente disse. Escrevê-las no mesmo caso faria o cartão anunciar "o agente
  # disse algo marcado" sobre uma cliente que estava reclamando, que é apontar
  # o culpado errado no único lugar onde o operador confia no rótulo.
  def flagged_findings
    signals.flagged.filter_map do |conversation_id, signal|
      detail = details.for(conversation_id)
      next if detail.nil?

      if signal[:flag] == 'cliente_insatisfeito'
        unhappy_finding(detail, signal)
      else
        flagged_finding(detail, signal)
      end
    end
  end

  def flagged_finding(detail, signal)
    phrase = FLAG_PHRASES[signal[:flag]] || 'disse algo que os guardrails marcaram'
    build(detail, 'resposta_marcada',
          detail: "Nesta conversa o agente #{phrase}.",
          excerpt: signal[:excerpt], occurred_at: signal[:at],
          metadata: { 'flag' => signal[:flag] })
  end

  def unhappy_finding(detail, signal)
    build(detail, 'cliente_insatisfeito',
          detail: "#{who(detail)} demonstrou insatisfação durante o atendimento.",
          excerpt: detail.excerpt.presence || signal[:excerpt], occurred_at: signal[:at],
          metadata: { 'flag' => signal[:flag] })
  end

  def last_activity(conversation_id)
    row = activity.rows[conversation_id]
    [row&.last_in, row&.last_out].compact.max || @now
  end

  def who(detail)
    detail.contact_name.presence || 'O cliente'
  end

  # "há 31h" e não "há 1.3 dias": o operador pensa nesta tela em horas, e um
  # número quebrado de dias obriga ele a fazer a conta de cabeça para saber se
  # o caso é de agora ou de anteontem.
  def humanized(hours)
    return "há #{hours.round} horas" if hours < 48

    "há #{(hours / 24).round} dias"
  end

  def build(subject, case_key, severity: nil, **attrs)
    {
      conversation_id: subject.conversation_id, conversation_display_id: subject.display_id,
      contact_id: subject.contact_id, ai_assistant_id: subject.assistant_id,
      case_key: case_key, severity: severity || Cases.severity_for(case_key),
      title: Cases.title_for(case_key), author: subject.author, source: 'triage',
      value_cents_brl: subject.value_cents, metadata: {}
    }.merge(attrs)
  end
end
