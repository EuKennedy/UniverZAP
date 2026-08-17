# A varredura: monta a janela, roda as verificações ligadas sobre cada agente da
# conta, e grava a rodada com as sugestões que saíram dela.
#
# Duas decisões que valem mais que o código:
#
# 1. A janela é de 30 dias e a cadência é semanal, de propósito sobrepostas. Uma
#    semana de um salão são seis conversas, e conclusão nenhuma sobrevive a isso.
#    Rodar toda semana sobre os últimos 30 dias dá amostra para concluir e
#    frequência para o operador perceber uma piora antes do fim do mês.
#
# 2. Amostra pequena não vira conclusão fraca, vira recusa. O Gerente registra
#    `insufficient_data` e diz quantas conversas faltam. A alternativa seria
#    apontar "37% de queda na conversão" apoiado em três conversas, e uma feature
#    que erra assim na primeira semana não é usada na segunda.
class Ai::Manager::AnalysisService
  # A janela que cada rodada olha, e a régua de amostra.
  #
  # 20 pela mesma razão que Ai::PromotionPolicy exige 20 duelos: porcentagem
  # tirada de três conversas é ruído vestido de número. Aqui o custo de errar é
  # maior ainda, porque a saída não é um gráfico, é uma mudança proposta no que o
  # agente fala com cliente.
  WINDOW_DAYS = 30
  MIN_CONVERSATIONS = 20

  # De quanto em quanto tempo a varredura automática acontece. Tem que continuar
  # igual ao cron de Ai::Manager::WeeklySchedulerJob em config/schedule.yml: é
  # daqui que a tela calcula quando é a próxima, e as duas discordarem faria o
  # painel prometer uma data que não vai acontecer.
  CADENCE = 7.days

  def initialize(account:, period: nil, triggered_by: 'schedule', user: nil)
    @account = account
    @requested_period = period || Ai::Reports::Period.from_days(WINDOW_DAYS)
    @triggered_by = triggered_by
    @user = user
  end

  def perform
    run = start_run
    analyse(run)
    run
  rescue StandardError => e
    mark_failed(run, e)
    run
  end

  private

  def scope
    @scope ||= Ai::Manager::Scope.for_account(@account, @requested_period)
  end

  def start_run
    Ai::Manager::Run.create!(
      account: @account, status: 'running', triggered_by: @triggered_by, user_id: @user&.id,
      started_at: Time.current, period_start: scope.period.starts_at, period_end: scope.period.ends_at
    )
  end

  def analyse(run)
    analysed = scope.conversations_count
    return refuse(run, analysed) if analysed < MIN_CONVERSATIONS

    checks = Ai::Manager::Checks.enabled_for(@account)
    # Só os agentes ligados, a mesma régua que Ai::Manager::WeeklySchedulerJob usa
    # para escolher a conta. Um agente desligado não fala com ninguém, e propor
    # mudança de instrução para ele é encher a fila com cartas sobre um agente que
    # o operador já tirou do ar. A tela continua mostrando as notas dele: histórico
    # é histórico, e é a fila que precisa ser curta.
    created = @account.ai_assistants.active.order(:id).to_a.sum { |assistant| audit(run, assistant, checks) }
    finish(run, analysed, created)
  end

  # Terminou certa e não concluiu nada. Fica `done` e não `failed` porque nada
  # quebrou: uma conta nova precisa ler "faltam 14 conversas" e não uma tela
  # vermelha dizendo que a auditoria falhou.
  def refuse(run, analysed)
    run.update!(
      status: 'done', finished_at: Time.current, conversations_analysed: analysed, cost_cents_brl: 0,
      summary: {
        'insufficient_data' => true, 'analysed' => analysed,
        'needed' => MIN_CONVERSATIONS, 'missing' => MIN_CONVERSATIONS - analysed
      }
    )
  end

  # O custo gravado é o mesmo número que a tela mostrou antes de rodar, e hoje
  # os dois são zero porque nenhuma verificação da v1 chama modelo. No dia em que
  # uma chamar, este campo tem que passar a ler o consumido de verdade: uma
  # estimativa gravada como fato é exatamente o tipo de número que ninguém
  # confere depois.
  def finish(run, analysed, created)
    run.update!(
      status: 'done', finished_at: Time.current, conversations_analysed: analysed,
      cost_cents_brl: Ai::Manager::CostEstimator.new(account: @account, scope: scope).cents,
      summary: { 'insufficient_data' => false, 'analysed' => analysed, 'suggestions_created' => created }
    )
  end

  def mark_failed(run, error)
    Rails.logger.error("[Athenas gerente] rodada falhou account=#{@account.id}: #{error.message}")
    ChatwootExceptionTracker.new(error, account: @account).capture_exception
    run&.update(status: 'failed', finished_at: Time.current, summary: { 'error' => error.message.to_s.truncate(300) })
  end

  # Quantas sugestões este agente gerou nesta rodada.
  def audit(run, assistant, checks)
    agent_scope = scope.for_assistant(assistant)
    findings = checks.flat_map { |check| safely(check, agent_scope) }
    # Uma sugestão por verificação, por agente, por rodada. A verificação já
    # promete no máximo um achado, e isto é o que garante que a promessa valha
    # mesmo quando alguém escrever a quinta classe sem reler o contrato.
    findings.uniq { |finding| finding[:check_key] }
            .count { |finding| persist(run, assistant, finding) }
  end

  # Uma verificação que estoura não pode levar as outras três junto. O log fica
  # com o nome dela para alguém consertar; a rodada segue e entrega o que
  # conseguiu, porque metade da auditoria vale mais que nenhuma.
  def safely(check, agent_scope)
    check.run(agent_scope)
  rescue StandardError => e
    Rails.logger.error(
      "[Athenas gerente] verificação #{check.key} falhou account=#{@account.id} " \
      "assistant=#{agent_scope.assistant&.id}: #{e.message}"
    )
    []
  end

  def persist(run, assistant, finding)
    return false if already_open?(assistant, finding[:check_key])

    Ai::Manager::Suggestion.create!(
      finding.slice(:check_key, :severity, :target, :title, :rationale, :evidence, :proposed)
             .merge(account: @account, ai_assistant: assistant, ai_manager_run: run, status: 'pending')
    )
    true
  rescue ActiveRecord::RecordNotUnique
    # A rede de baixo do índice único. Chegar aqui significa que a deduplicação
    # em Ruby não pegou, e o certo é não criar a segunda em vez de derrubar a
    # rodada inteira.
    false
  end

  # Já existe uma carta aberta sobre a mesma coisa, deste mesmo agente. Repetir
  # toda semana o que o operador ainda não decidiu transforma a fila num lugar
  # que ninguém abre.
  def already_open?(assistant, check_key)
    Ai::Manager::Suggestion.open_items
                           .exists?(account_id: @account.id, ai_assistant_id: assistant.id, check_key: check_key)
  end
end
