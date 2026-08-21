# A janela por onde o Gerente olha: uma conta, um período, e opcionalmente um
# agente dela.
#
# Existe por uma razão de isolamento e não de conveniência. Toda leitura do
# Gerente sai daqui, e toda consulta daqui filtra `account_id` SEMPRE, mesmo
# quando o `ai_assistant_id` já implicaria a conta. É redundante de propósito:
# quem escrever a quinta verificação daqui a um ano não vai reler esta regra, e
# um filtro esquecido numa auditoria significa uma conta lendo a conversa de
# outra. Nenhuma verificação recebe um model, recebe este objeto.
#
# `assistant` nulo significa "a conta inteira", que é o que a nota de topo do
# painel mede. As verificações sempre recebem um escopo com agente: elas auditam
# um agente por vez, porque a régua é a história dele contra o período anterior.
class Ai::Manager::Scope
  # Um agendamento, venha ele da agenda do Google ou do livro do salão.
  #
  # Struct e não Hash porque quem lê isto compara horário: um `[:starts_at]`
  # digitado `[:start_at]` devolveria nil calado, e uma verificação crítica que
  # falha calada é exatamente o defeito que este leitor existe para consertar.
  Booking = Struct.new(:id, :conversation_id, :starts_at, :created_at, :source, keyword_init: true)

  # Teto de agendamentos lidos por agenda numa rodada. Uma auditoria semanal não
  # é relatório histórico, e o teto é o que garante que a varredura de uma conta
  # grande custe o mesmo que a de uma pequena. Lido de cada agenda e de novo do
  # resultado: os 500 mais recentes das duas juntas estão sempre dentro dos 500
  # mais recentes de cada uma.
  MAX_BOOKINGS = 500

  # Só o que tem cara de data e hora ISO entra no parse. O horário do belezaki é
  # string escrita pelo salão e não coluna de tempo, e `TimeZone#parse` é
  # generoso demais para esta porta: ele aceita "14h" e devolve hoje às 14:00.
  # Horário inventado é pior que agendamento nenhum numa verificação crítica.
  ISO_TIME = /\A\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}/

  attr_reader :account, :assistant, :period, :zone

  # O relógio do negócio, não o do servidor. Um horário prometido só pode ser
  # comparado com o horário agendado no fuso em que a agenda foi escrita.
  def self.for_account(account, period)
    zone = Ai::Reports::AccountClock.new(account).zone
    new(account: account, period: period.align_to(zone), zone: zone)
  end

  def initialize(account:, period:, zone:, assistant: nil, commercial: nil)
    @account = account
    @period = period
    @zone = zone
    @assistant = assistant
    @commercial = commercial
  end

  # O mesmo período e a mesma conta, estreitado num agente. A métrica comercial
  # viaja junto porque ela é da conta inteira e responde por agente: instanciada
  # de novo em cada escopo, uma conta com seis agentes pagaria seis varreduras
  # dos mesmos ledgers.
  def for_assistant(assistant)
    self.class.new(account: @account, period: @period, zone: @zone, assistant: assistant, commercial: commercial)
  end

  # A janela imediatamente anterior, de mesma duração. É contra ela que as três
  # notas são lidas: a régua do agente é a história dele, não o irmão.
  def previous
    self.class.new(account: @account, period: @period.previous, zone: @zone, assistant: @assistant)
  end

  def invocations
    @invocations ||= narrow(Ai::Invocation.where(account_id: @account.id, created_at: @period.range))
  end

  # Chamadas que produziram uma mensagem que um cliente de verdade recebeu.
  # Playground fora: ninguém precisa auditar a resposta dada a um cliente falso.
  def replies
    @replies ||= invocations.live.replies
  end

  # Mensagens entregues, contadas por mensagem e não por linha. Um turno que usa
  # a agenda cobra várias chamadas e todas carregam o mesmo message_id, então
  # contar linhas mediria o quanto o agente precisou tentar.
  def messages_count
    @messages_count ||= replies.distinct.count(:message_id)
  end

  def conversations_count
    @conversations_count ||= replies.where.not(conversation_id: nil).distinct.count(:conversation_id)
  end

  # Quantas conversas cada agente da conta atendeu na janela. É daqui que a
  # varredura descobre quem TRABALHOU, que é diferente de quem está ligado: um
  # agente desligado ontem depois de trinta atendimentos tem lição válida, e um
  # agente ligado sem inbox nenhuma não tem nada a ensinar.
  def conversations_by_assistant
    @conversations_by_assistant ||= replies.where.not(conversation_id: nil)
                                           .group(:ai_assistant_id).distinct.count(:conversation_id)
  end

  # As conversas de um subconjunto de agentes, que é o que a régua de amostra
  # precisa medir: contar a conta inteira e auditar um subconjunto é como o
  # resumo passou a afirmar "analisei 36 conversas e não achei nada" sobre
  # agentes que não tiveram conversa nenhuma.
  #
  # Em DISTINTO e não somando as linhas por agente: dois agentes do mesmo salão
  # atendem a mesma conversa, e somar contaria essa conversa duas vezes
  # justamente na régua que decide se existe material para concluir.
  def conversations_count_for(assistant_ids)
    return 0 if assistant_ids.blank?

    replies.where(ai_assistant_id: assistant_ids).where.not(conversation_id: nil)
           .distinct.count(:conversation_id)
  end

  # O número que a conversa tem na URL do Chatwoot, que é `display_id` e não a
  # chave primária: os dois quase nunca coincidem, porque o display_id é uma
  # sequência por conta. Uma consulta para todos os ids pedidos, e filtrada por
  # conta como todo o resto daqui.
  def display_ids_for(conversation_ids)
    return {} if conversation_ids.blank?

    Conversation.where(account_id: @account.id, id: conversation_ids).pluck(:id, :display_id).to_h
  end

  def appointments
    @appointments ||= narrow(Ai::Calendar::Appointment.where(account_id: @account.id, created_at: @period.range))
  end

  def revenue_events
    @revenue_events ||= narrow(Ai::RevenueEvent.where(account_id: @account.id, occurred_at: @period.range))
  end

  # As DUAS agendas numa lista só, e é a única forma honesta de auditar
  # agendamento nesta base.
  #
  # `ai_calendar_appointments` é escrita SÓ pelo caminho do Google
  # (Ai::Calendar::BookService e Ai::Calendar::SchedulingTools). O salão que usa
  # belezaki guarda o livro dele e nos deixa apenas a confirmação, que
  # Ai::Belezaki::BookingRecorder grava no ledger de receita. Quem lesse só a
  # primeira tabela ficaria mudo para todo cliente de salão sem dar erro nenhum,
  # que é o jeito mais silencioso de uma feature falhar, e foi o que aconteceu
  # com promised_time_mismatch: ela nasceu de uma falha do belezaki e era
  # estruturalmente incapaz de enxergar aquele caso.
  #
  # Mais recente primeiro, porque o cartão mostra o pior caso como evidência e o
  # caso que o operador consegue conferir é o de ontem, não o de vinte dias.
  def bookings
    @bookings ||= (google_bookings + belezaki_bookings).sort_by { |booking| -booking.created_at.to_f }
                                                       .first(MAX_BOOKINGS)
  end

  # `last_seen_at` e não `created_at`, igual ao radar comercial: um lead esquenta
  # e esfria, e a pergunta é quais se mexeram no período.
  def leads
    @leads ||= narrow(Ai::LeadOpportunity.where(account_id: @account.id, last_seen_at: @period.range))
  end

  def commercial
    @commercial ||= Ai::Reports::CommercialMetrics.new(account: @account, period: @period, zone: @zone)
  end

  # O que este agente vendeu e agendou, já calculado pelo painel comercial.
  def commercial_row
    return {} if @assistant.nil?

    commercial.by_agent[@assistant.id] || {}
  end

  # O que o agente gastou de crédito na janela, em centavos. Lido de `cost_brl`,
  # que é a coluna que o painel de ROI divide receita por, e não do ledger: o
  # ledger é da conta e não sabe dizer qual agente gastou.
  #
  # Atendimento de verdade só: fora o playground e fora os duelos do laboratório.
  # É a mesma exclusão de Ai::RoiService, e ela não é preciosismo de simetria.
  # Sem ela, aprovar uma sugestão de instrução PIORAVA a nota de custo da semana
  # seguinte, porque a própria aprovação enfileira duelos de A/B contra o agente
  # (Ai::Manager::Applier#queue_duels) e eles são cobrados na mesma coluna. O
  # operador seguia a recomendação do Gerente e o Gerente lhe mostrava um custo
  # maior por isso, além de um número que não bate com o do painel comercial.
  def cost_cents_brl
    @cost_cents_brl ||= (served.sum(:cost_brl).to_f * 100).round
  end

  # As conversas em que ALGO foi agendado, das duas agendas, e só os ids.
  #
  # Existe separado de `bookings` por causa do teto. Lá o teto protege uma
  # varredura de conta grande, e cortar em 500 só significa auditar os 500 mais
  # recentes. Aqui a lista serve para ABSOLVER, e um teto viraria acusação: a
  # conversa que ficou de fora do corte passa a parecer que nunca agendou, e o
  # agente que trabalhou certo leva um cartão dizendo que prometeu e não
  # cumpriu. Lista de exclusão precisa ser completa ou não serve.
  #
  # Só os ids porque é disso que o cruzamento precisa, e assim as duas consultas
  # não carregam linha nenhuma para a memória.
  def booked_conversation_ids
    @booked_conversation_ids ||= (
      appointments.booked.where.not(conversation_id: nil).distinct.pluck(:conversation_id) +
      revenue_events.belezaki_bookings.where.not(conversation_id: nil).distinct.pluck(:conversation_id)
    ).to_set
  end

  private

  # `conversation_id` não nulo nas duas agendas: um agendamento sem conversa não
  # tem confirmação para comparar, e carregá-lo só engordaria o teto.
  def google_bookings
    appointments.booked.where.not(conversation_id: nil)
                .order(created_at: :desc).limit(MAX_BOOKINGS)
                .map do |row|
      Booking.new(id: row.id, conversation_id: row.conversation_id, starts_at: row.starts_at,
                  created_at: row.created_at, source: 'google')
    end
  end

  def belezaki_bookings
    revenue_events.belezaki_bookings.where.not(conversation_id: nil)
                  .order(occurred_at: :desc).limit(MAX_BOOKINGS)
                  .filter_map { |row| belezaki_booking(row) }
  end

  # `occurred_at` como o instante do agendamento, e não `created_at`: é por ele
  # que a janela filtra, e o recorder o escreve uma vez só, na entrada
  # (`occurred_at ||= Time.current`), justamente para que a comanda aberta na
  # manhã seguinte não mova a venda de noite. As duas colunas nascem iguais aqui,
  # e escolher a que a janela usa é o que impede uma linha de entrar no período
  # e ser comparada contra outro instante.
  #
  # Linha que não parseia é DESCARTADA, nunca vira agendamento com horário nulo:
  # um nil aqui estouraria dentro da verificação, o `safely` do AnalysisService
  # engoliria a rodada inteira daquele agente, e a auditoria voltaria a falhar
  # calada.
  def belezaki_booking(row)
    starts_at = local_time(row.metadata.to_h['starts_at'])
    return nil if starts_at.nil?

    Booking.new(id: row.id, conversation_id: row.conversation_id, starts_at: starts_at,
                created_at: row.occurred_at, source: 'belezaki')
  end

  # Parseado no fuso do NEGÓCIO para os dois formatos que o salão pode devolver:
  # com deslocamento, ele manda; sem deslocamento, a string é hora local do
  # salão e lê-la como UTC jogaria o agendamento três horas para o lado, que
  # numa verificação de horário é a diferença entre acusar e absolver.
  def local_time(value)
    text = value.to_s
    return nil unless text.match?(ISO_TIME)
    return nil unless real_date?(text)

    @zone.parse(text)
  rescue ArgumentError, TypeError
    nil
  end

  # O regex prova a FORMA e não a existência do dia, e `parse` é leniente: ele
  # não levanta erro para `2026-02-30`, devolve 2 de março. A linha passava
  # inteira pelo rescue e virava agendamento num dia que o salão nunca teve, com
  # a data errada indo para dentro da verificação de horário.
  #
  # É a mesma leniência que o InputGuard do belezaki fecha do outro lado, onde
  # `date=2026-02-30` respondia 200 com os horários reais de 2 de março.
  def real_date?(text)
    year, month, day = text[0, 10].split('-').map(&:to_i)
    Date.valid_date?(year, month, day)
  end

  # Todas as chamadas que serviram cliente de verdade, e não só as que viraram
  # mensagem: um turno que consulta a agenda cobra várias chamadas e todas são
  # custo de atender.
  def served
    invocations.live.where.not(phase: 'replay')
  end

  # O único lugar onde o agente entra no filtro. Uma verificação não monta
  # consulta sozinha, então não existe caminho para ela esquecer disto.
  def narrow(relation)
    @assistant.nil? ? relation : relation.where(ai_assistant_id: @assistant.id)
  end
end
