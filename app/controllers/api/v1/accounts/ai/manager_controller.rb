# O Gerente: as notas da conta, a fila de sugestões e o catálogo de verificações.
#
# `check_authorization` herdado NÃO é usado aqui, e isso é deliberado. Ele deriva
# o model do nome da controller, "manager" viraria a classe `Manager`, que não
# existe nesta base, e a requisição morreria como NameError antes de qualquer
# permissão ser consultada. Foi assim que um painel inteiro caiu antes; a saída é
# a mesma de Api::V1::Accounts::Ai::ReportsController: nomear a política.
#
# Leitura passa pela mesma porta de Relatórios, porque mostra a mesma classe de
# número (gasto, receita, conversão). Escrita exige administrador por cima disso:
# aprovar uma sugestão muda o que o agente fala com cliente, e ReportPolicy é
# extensível por enterprise, então depender só dela seria apostar que ninguém vai
# afrouxá-la um dia.
class Api::V1::Accounts::Ai::ManagerController < Api::V1::Accounts::BaseController
  before_action :ensure_manager_access
  before_action :ensure_admin, only: [:approve, :dismiss, :create_run, :update_check]
  before_action :fetch_suggestion, only: [:approve, :dismiss]

  # Teto da fila numa resposta. Acima disso ninguém lê, e a decisão que importa
  # está nas primeiras, que vêm por severidade.
  MAX_SUGGESTIONS = 100

  def overview
    render json: Ai::Manager::Overview.new(account: Current.account, period: period).perform
  end

  def suggestions
    render json: { payload: suggestion_scope.by_urgency.limit(MAX_SUGGESTIONS).map(&:push_event_data) }
  end

  # Repetir a aprovação continua devolvendo 200, porque isso é o segundo clique
  # no mesmo botão e o Applier já não aplica duas vezes. Aprovar o que foi
  # DISPENSADO é outra coisa: é contradizer uma decisão que o operador já tomou,
  # e a tela precisa dizer isso em vez de responder "ok" sem ter feito nada.
  def approve
    return render_could_not_create_error('Esta sugestão foi dispensada') if @suggestion.status == 'dismissed'

    applied = Ai::Manager::Applier.new(suggestion: @suggestion, user: Current.user).perform
    render json: { status: applied.status, applied_as: applied.applied_as }
  end

  # Só de `pending`. Dispensar uma sugestão já aplicada não desfaz nada, apenas
  # apagaria da tela o registro de uma mudança que está no ar.
  def dismiss
    return render_could_not_create_error('Esta sugestão já foi decidida') if @suggestion.decided?

    @suggestion.update!(status: 'dismissed', dismissed_reason: params[:reason].to_s.truncate(255).presence)
    render json: { status: @suggestion.status }
  end

  def estimate
    render json: Ai::Manager::CostEstimator.new(account: Current.account, period: period).perform
  end

  # Síncrono de propósito: as quatro verificações da v1 só leem o log, não
  # chamam modelo nenhum, e devolver a rodada já terminada evita a tela ter que
  # ficar perguntando se acabou. A linha da rodada existe desde o primeiro
  # instante, então tornar isto assíncrono um dia não muda este contrato.
  def create_run
    run = Ai::Manager::AnalysisService.new(
      account: Current.account, period: period, triggered_by: 'manual', user: Current.user
    ).perform
    render json: { run_id: run&.id, status: run&.status || 'failed' }
  end

  def checks
    disabled = Ai::Manager::CheckSetting.disabled_keys_for(Current.account)
    payload = Ai::Manager::Checks.all.map do |check|
      check.descriptor.merge(enabled: !disabled.include?(check.key))
    end
    render json: { payload: payload }
  end

  def update_check
    setting = Current.account.ai_manager_check_settings.find_or_initialize_by(check_key: known_check_key)
    setting.update!(enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]))
    render json: { key: setting.check_key, enabled: setting.enabled }
  end

  private

  # Sem filtro quando o parâmetro não é um estado conhecido, e não um padrão
  # escondido: a tela pede `?status=pending` explicitamente, e um filtro implícito
  # faria a lista "sumir" com as sugestões já decididas sem ninguém ter pedido.
  def suggestion_scope
    scope = Current.account.ai_manager_suggestions.includes(:ai_assistant)
    status = params[:status].to_s
    return scope unless Ai::Manager::Suggestion::STATUSES.include?(status)

    scope.where(status: status)
  end

  def known_check_key
    check = Ai::Manager::Checks.find(params[:key])
    raise ActiveRecord::RecordNotFound, "verificação desconhecida: #{params[:key]}" if check.nil?

    check.key
  end

  # `since`/`until` em epoch, igual ao resto de Relatórios, e `days` como
  # alternativa.
  #
  # Nil quando a requisição não pediu janela nenhuma, e não o padrão de
  # Ai::Reports::Period: a janela da auditoria é WINDOW_DAYS, decidida pelo
  # próprio Gerente, e deixar o padrão de Relatórios responder por ela faria a
  # auditoria mudar de tamanho no dia em que outra tela mudasse o dela.
  def period
    return nil if params[:since].blank? && params[:until].blank? && params[:days].blank?

    Ai::Reports::Period.from_params(
      since: params[:since], until_at: params[:until], days: params[:days]
    )
  end

  # A sugestão SEMPRE sai da conta autenticada. É esta linha que faz uma
  # sugestão de outra conta devolver 404 em vez de ser aprovada.
  def fetch_suggestion
    @suggestion = Current.account.ai_manager_suggestions.find(params[:id])
  end

  def ensure_manager_access
    authorize(:report, :view?)
  end

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end
end
