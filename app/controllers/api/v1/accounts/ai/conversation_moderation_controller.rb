# O moderador de conversas: a lista de achados, o preço da próxima leitura e o
# disparo dela.
#
# Controller própria e não mais quatro ações na do Gerente, porque a fronteira
# aqui é de escrita e não de tema. `index` e `estimate` só leem, e passam pela
# mesma porta de Relatórios. `create_scan` gasta dinheiro do operador, e por isso
# exige administrador, do mesmo jeito que aprovar uma sugestão exige.
#
# `check_authorization` herdado continua fora, pela mesma razão documentada em
# Api::V1::Accounts::Ai::ManagerController: ele derivaria o model do nome da
# controller e a requisição morreria como NameError antes de qualquer permissão
# ser consultada.
class Api::V1::Accounts::Ai::ConversationModerationController < Api::V1::Accounts::BaseController
  before_action :ensure_moderation_access
  before_action :ensure_admin, only: [:create_scan]

  # A leitura que a tela faz a cada mudança de filtro. Não gasta nada: fatia o
  # que a última varredura já gravou.
  def index
    render json: Ai::Manager::Conversations::Listing.new(
      account: Current.account, days: params[:days], author: params[:author], case_key: params[:case_key]
    ).payload
  end

  # O preço antes do clique. Roda só a triagem, que é consulta.
  def estimate
    render json: Ai::Manager::Conversations::Estimator.new(account: Current.account, hours: window_hours).perform
  end

  # Uma varredura em andamento por conta.
  #
  # O segundo clique devolve a que já está rodando em vez de abrir outra, e isso
  # é uma proteção de dinheiro e não de banco: duas varreduras simultâneas leem
  # as mesmas conversas e cobram duas vezes pelo mesmo resultado, porque o
  # índice único faz a segunda apenas sobrescrever os achados da primeira.
  # Uma varredura que passou disto não está rodando, está pendurada: o job
  # morreu com o worker, ou um deploy passou por cima dele. Sessenta leituras
  # levam minutos, não meia hora.
  STALE_AFTER = 30.minutes

  def create_scan
    running = live_scan
    return render json: running.push_event_data.merge(already_running: true) if running

    scan = Current.account.ai_manager_conversation_scans.create!(
      window_hours: Ai::Manager::ConversationScan.window_for(window_hours), user_id: Current.user&.id
    )
    Ai::Manager::ConversationScanJob.perform_later(scan.id)
    render json: scan.push_event_data
  end

  # O que a tela consulta enquanto espera. A varredura é assíncrona porque chama
  # modelo uma vez por conversa, e segurar a requisição entregaria um timeout de
  # proxy no lugar do resultado.
  def show_scan
    scan = Current.account.ai_manager_conversation_scans.find(params[:id])
    render json: scan.push_event_data
  end

  private

  # A varredura em andamento, se ainda faz sentido chamá-la assim.
  #
  # Sem o corte por idade, uma varredura interrompida ficava 'running' para
  # sempre: o botão de analisar sumia da aba e a conta perdia a feature, sem
  # nada na tela que a destravasse. Marcá-la como falha é o que devolve o botão
  # e conta o que aconteceu, em vez de deixar o operador achando que ainda está
  # processando.
  def live_scan
    running = Current.account.ai_manager_conversation_scans.find_by(status: 'running')
    return nil if running.nil?
    return running if running.created_at > STALE_AFTER.ago

    running.update(
      status: 'failed', finished_at: Time.current,
      summary: running.summary.merge('error' => 'A leitura anterior foi interrompida antes de terminar.')
    )
    nil
  end

  def window_hours
    Ai::Manager::ConversationScan.window_for(params[:hours])
  end

  def ensure_moderation_access
    authorize(:report, :view?)
  end

  def ensure_admin
    render_unauthorized('Administrator privileges required') unless Current.account_user&.administrator?
  end
end
