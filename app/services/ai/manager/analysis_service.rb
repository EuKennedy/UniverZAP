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

  # A amostra é medida no MESMO conjunto que a auditoria varre, e não na conta
  # inteira. Contar 36 conversas da conta e varrer um agente que teve zero é
  # como o resumo passou a afirmar "analisei 36 conversas e não achei nada" sem
  # ter olhado uma linha sequer.
  def analyse(run)
    audited = audited_assistants
    analysed = scope.conversations_count_for(audited.map(&:id))
    return refuse(run, analysed, audited) if analysed < MIN_CONVERSATIONS

    checks = Ai::Manager::Checks.enabled_for(@account)
    breakdown = audited.map { |assistant| agent_row(assistant, audit(run, assistant, checks)) }
    finish(run, analysed, breakdown)
  end

  # Quem TRABALHOU na janela, e não quem está ligado.
  #
  # Furo visto em produção: a conta auditada tinha um único agente ativo, sem
  # inbox nenhuma e portanto sem uma conversa sequer, enquanto os dois que
  # atendiam de verdade estavam desligados. A varredura pulava os dois, não
  # olhava nada, e gravava um resumo dizendo que estava tudo bem.
  #
  # Um agente que atendeu trinta clientes e foi desligado ontem tem lição
  # válida, porque a instrução dele segue escrita e volta ao ar no dia em que o
  # operador religar. Um agente ligado que nunca falou não tem nada a ensinar.
  #
  # A queda para os ativos é para conta nova: sem ninguém com tráfego, a rodada
  # ainda precisa dizer quantas conversas faltam em vez de não dizer nada.
  def audited_assistants
    @audited_assistants ||= begin
      worked = scope.conversations_by_assistant.keys
      relation = worked.empty? ? @account.ai_assistants.active : @account.ai_assistants.where(id: worked)
      relation.order(:id).to_a
    end
  end

  # "Zero sugestões porque não havia o que analisar" e "zero sugestões porque
  # está tudo bem" são coisas opostas, e escreviam o mesmo texto. Uma linha por
  # agente auditado é o que separa as duas: quem não teve conversa aparece com
  # zero conversas ao lado do zero sugestões.
  def agent_row(assistant, suggestions)
    {
      'id' => assistant.id, 'name' => assistant.name,
      'conversations' => scope.conversations_by_assistant[assistant.id].to_i,
      'suggestions' => suggestions
    }
  end

  # Terminou certa e não concluiu nada. Fica `done` e não `failed` porque nada
  # quebrou: uma conta nova precisa ler "faltam 14 conversas" e não uma tela
  # vermelha dizendo que a auditoria falhou.
  def refuse(run, analysed, audited)
    run.update!(
      status: 'done', finished_at: Time.current, conversations_analysed: analysed, cost_cents_brl: 0,
      summary: {
        'insufficient_data' => true, 'analysed' => analysed,
        'needed' => MIN_CONVERSATIONS, 'missing' => MIN_CONVERSATIONS - analysed,
        'agents' => audited.map { |assistant| agent_row(assistant, 0) }
      }
    )
  end

  # O custo gravado é o mesmo número que a tela mostrou antes de rodar, e hoje
  # os dois são zero porque nenhuma verificação da v1 chama modelo. No dia em que
  # uma chamar, este campo tem que passar a ler o consumido de verdade: uma
  # estimativa gravada como fato é exatamente o tipo de número que ninguém
  # confere depois.
  def finish(run, analysed, breakdown)
    run.update!(
      status: 'done', finished_at: Time.current, conversations_analysed: analysed,
      cost_cents_brl: Ai::Manager::CostEstimator.new(account: @account, scope: scope).cents,
      summary: {
        'insufficient_data' => false, 'analysed' => analysed,
        'suggestions_created' => breakdown.sum { |row| row['suggestions'] },
        'agents' => breakdown
      }
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
    unique = findings.uniq { |finding| finding[:check_key] }
    with_display_ids(unique, agent_scope).count { |finding| persist(run, assistant, finding) }
  end

  # O botão "abrir conversa" do cartão, que é a peça em que o cartão inteiro se
  # apoia: sem conferir a conversa, aprovar é confiar no parecer de um robô
  # sobre o trabalho de outro robô.
  #
  # A URL do Chatwoot é /accounts/:id/conversations/:display_id, e `display_id` é
  # a sequência POR CONTA, não a chave primária que a evidência carrega. Os dois
  # quase nunca coincidem, então o botão abria a conversa de outro cliente ou
  # uma tela de erro. Traduzido aqui e não no front porque o front não tem como
  # fazer isso sem uma chamada a mais, e uma consulta para todos os achados do
  # agente, não uma por sugestão.
  #
  # `conversation_id` fica onde está: é a chave que qualquer leitura de banco
  # sobre a evidência precisa. Nulo quando a conversa já foi apagada, e o cartão
  # esconde o botão em vez de mostrar um link quebrado.
  def with_display_ids(findings, agent_scope)
    # `grep(Hash)` e não acesso direto: uma verificação que devolva evidência
    # malformada não pode derrubar a rodada inteira aqui fora, onde o `safely`
    # já não alcança.
    evidences = findings.map { |finding| finding[:evidence] }.grep(Hash)
    ids = evidences.filter_map { |evidence| evidence['conversation_id'] }
    return findings if ids.empty?

    display_ids = agent_scope.display_ids_for(ids)
    evidences.each { |evidence| evidence['conversation_display_id'] = display_ids[evidence['conversation_id']] }
    findings
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
