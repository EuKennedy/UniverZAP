# Quanto custa rodar o Gerente agora, para a tela mostrar ANTES de alguém
# clicar.
#
# Hoje a resposta é zero, e isso é uma afirmação sobre o desenho e não um campo
# esquecido: as quatro verificações da v1 leem o log e cruzam ledgers, sem uma
# única chamada de modelo. Não existe LLM juiz nesta versão porque um juiz
# custaria uma chamada por conversa auditada e devolveria uma opinião, quando o
# que já está gravado (bandeiras automáticas, agendamento, receita, conversa
# morta) são fatos.
#
# O número continua sendo calculado em vez de escrito como zero porque cada
# verificação declara o próprio custo por conversa. No dia em que a quinta
# precisar de um modelo, o preço aparece nesta tela sozinho, e nenhuma tela
# precisa ser mexida para isso.
class Ai::Manager::CostEstimator
  def initialize(account:, scope: nil, period: nil)
    @account = account
    @scope = scope
    @period = period
  end

  def perform
    { credits_cents_brl: cents, conversations: conversations }
  end

  def cents
    per_conversation * conversations
  end

  def conversations
    @conversations ||= scope.conversations_count
  end

  private

  # Só as ligadas. Uma verificação desligada não roda, então cobrar por ela na
  # estimativa seria vender o que não vai acontecer.
  def per_conversation
    Ai::Manager::Checks.enabled_for(@account).sum(&:cost_per_conversation_cents)
  end

  def scope
    @scope ||= Ai::Manager::Scope.for_account(
      @account, @period || Ai::Reports::Period.from_days(Ai::Manager::AnalysisService::WINDOW_DAYS)
    )
  end
end
