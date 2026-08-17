# O topo da tela do Gerente: as três notas da conta, as mesmas três por agente, e
# o estado da própria auditoria.
#
# `data_sufficiency` viaja no mesmo payload das notas, e não num endpoint à
# parte, porque as notas não podem ser lidas sem ele. 62% de conversão apurados
# em quatro conversas e em quatrocentas são o mesmo número na tela e coisas
# completamente diferentes na vida, e a tela precisa poder dizer qual das duas
# está mostrando sem uma segunda requisição que pode não chegar.
class Ai::Manager::Overview
  def initialize(account:, period: nil)
    @account = account
    @requested_period = period || Ai::Reports::Period.from_days(Ai::Manager::AnalysisService::WINDOW_DAYS)
  end

  def perform
    {
      scores: scorecard(scope),
      agents: agents,
      last_run_at: last_run_at&.to_i,
      next_run_at: next_run_at&.to_i,
      pending_count: pending_count,
      data_sufficiency: data_sufficiency
    }
  end

  private

  def scope
    @scope ||= Ai::Manager::Scope.for_account(@account, @requested_period)
  end

  def scorecard(target)
    Ai::Manager::Scorecard.new(scope: target).perform
  end

  # Por nome, e não por nota. Ordenar por desempenho faria as linhas trocarem de
  # lugar entre uma semana e outra, e uma tabela que se reordena sozinha é uma
  # tabela em que ninguém acha o agente que veio procurar.
  def agents
    @account.ai_assistants.order(:name).map do |assistant|
      { id: assistant.id, name: assistant.name, scores: scorecard(scope.for_assistant(assistant)) }
    end
  end

  def last_run
    @last_run ||= @account.ai_manager_runs.completed.recent.first
  end

  def last_run_at
    last_run&.finished_at
  end

  # Contada da última varredura AUTOMÁTICA, e não da última qualquer. A cadência
  # que esta data promete é a do cron semanal, e um "rodar agora" numa quarta não
  # move o agendador: somar sete dias em cima dele faria o painel prometer quarta
  # que vem para uma varredura que vai acontecer na segunda.
  #
  # Nulo enquanto nunca rodou sozinho, de propósito. Antes da primeira varredura
  # automática não existe de onde contar a próxima, e devolver "daqui a sete
  # dias" seria a tela prometendo uma data que o agendador não conhece.
  def next_run_at
    last_scheduled_at && last_scheduled_at + Ai::Manager::AnalysisService::CADENCE
  end

  def last_scheduled_at
    return @last_scheduled_at if defined?(@last_scheduled_at)

    @last_scheduled_at = @account.ai_manager_runs.completed.where(triggered_by: 'schedule').recent.pick(:finished_at)
  end

  def pending_count
    Ai::Manager::Suggestion.pending.where(account_id: @account.id).count
  end

  # `needed` é a régua, não o que falta: com `analysed` ao lado, a tela consegue
  # dizer as duas coisas, e "20" é o número que não muda entre uma leitura e a
  # seguinte.
  def data_sufficiency
    analysed = scope.conversations_count
    needed = Ai::Manager::AnalysisService::MIN_CONVERSATIONS
    { enough: analysed >= needed, analysed: analysed, needed: needed }
  end
end
