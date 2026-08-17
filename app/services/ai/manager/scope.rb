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

  def appointments
    @appointments ||= narrow(Ai::Calendar::Appointment.where(account_id: @account.id, created_at: @period.range))
  end

  def revenue_events
    @revenue_events ||= narrow(Ai::RevenueEvent.where(account_id: @account.id, occurred_at: @period.range))
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

  private

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
