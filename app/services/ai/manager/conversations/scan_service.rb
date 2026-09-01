# A varredura: triagem de graça, leitura por modelo no que sobrou, e a gravação
# que faz a segunda rodada atualizar em vez de duplicar.
#
# A ordem é o produto. Invertê-la (ler tudo e filtrar depois) daria o mesmo
# painel por trinta vezes o preço, e o operador que pediu "sem comer token"
# pararia de rodar na segunda semana.
#
# Nada aqui é agendado. A varredura acontece quando alguém clica, e o resultado
# fica gravado: os filtros de dia da tela fatiam o que já existe e não disparam
# leitura nenhuma. É a diferença entre uma tela que custa quando você usa e uma
# que custa enquanto você dorme.
class Ai::Manager::Conversations::ScanService
  # Achado velho sai do banco. O filtro mais largo da tela é de 30 dias, então
  # 90 é folga de sobra para reler histórico, e sem um corte a tabela cresce
  # para sempre por causa de cartões que ninguém vai reabrir.
  PURGE_AFTER = 90.days

  def initialize(scan:, now: Time.current)
    @scan = scan
    @account = scan.account
    @now = now
  end

  def perform
    @scan.update!(status: 'running', started_at: @now)
    rows = triage.findings + reader.findings
    written = persist(rows)
    purge
    finish(written)
    @scan
  rescue StandardError => e
    fail_scan(e)
    @scan
  end

  private

  def since
    @since ||= @now - @scan.window_hours.hours
  end

  def triage
    @triage ||= Ai::Manager::Conversations::Triage.new(account: @account, since: since, now: @now)
  end

  def reader
    @reader ||= Ai::Manager::Conversations::Reader.new(
      account: @account, assistant: assistant, triage: triage, now: @now
    )
  end

  # Qualquer agente da conta com chave serve: o modelo da leitura é escolhido
  # aqui e a instrução é nossa, então o agente entra só como dono da chave e da
  # cota. O ativo tem preferência porque é o que o operador espera ver debitado.
  def assistant
    @assistant ||= @account.ai_assistants.active.first || @account.ai_assistants.first
  end

  # `upsert_all` e não um laço de save: duzentos achados viram uma escrita, e o
  # índice único resolve o "atualiza em vez de duplicar" dentro do banco, onde
  # duas varreduras simultâneas não conseguem se atropelar.
  #
  # A validação do modelo não roda num upsert, então a guarda tem que ser feita
  # aqui. Sem ela, uma chave de caso inventada por um modelo entraria no banco e
  # a tela mostraria um cartão sem título que ninguém sabe traduzir.
  def persist(rows)
    valid = rows.select { |row| acceptable?(row) }.map { |row| stamp(row) }
    return 0 if valid.empty?

    # rubocop:disable Rails/SkipsModelValidations
    # Pular a validação é o ponto: ela é feita em `acceptable?` antes, sobre um
    # Hash, e sem tocar no banco. A alternativa que o cop sugere seria um save
    # por achado, com uma consulta a mais cada, e ainda assim sem a garantia de
    # unicidade que só o índice dá quando duas varreduras rodam juntas.
    Ai::Manager::ConversationFinding.upsert_all(
      valid, unique_by: :idx_manager_findings_unique_case, update_only: REFRESHED
    )
    # rubocop:enable Rails/SkipsModelValidations
    valid.length
  end

  # O que uma releitura pode reescrever.
  #
  # `created_at` fica de fora de propósito: é quando aquele problema apareceu
  # PELA PRIMEIRA vez, e deixar o upsert atualizá-lo faria todo achado parecer
  # que nasceu hoje, apagando justamente a informação de que a mesma cliente
  # está pendurada há três leituras. O Rails já preserva o created_at no
  # conflito, então basta não pedir para reescrevê-lo.
  #
  # `updated_at` fica de fora por outro motivo, e este custou uma rodada de CI:
  # o Rails ANEXA a cláusula de updated_at ao `DO UPDATE SET` por conta própria
  # quando o modelo tem timestamps. Listá-lo aqui gera a coluna atribuída duas
  # vezes no mesmo comando, e o Postgres recusa com
  # "multiple assignments to same column".
  REFRESHED = %i[
    scan_id conversation_display_id contact_id ai_assistant_id severity title detail excerpt
    author source value_cents_brl metadata occurred_at waiting_since last_seen_at
  ].freeze

  def acceptable?(row)
    Ai::Manager::Conversations::Cases.known?(row[:case_key]) &&
      row[:conversation_id].present? && row[:occurred_at].present? &&
      Ai::Manager::ConversationFinding::AUTHORS.include?(row[:author].to_s)
  end

  # Todas as linhas com EXATAMENTE as mesmas chaves, sempre. O `upsert_all`
  # monta as colunas a partir da primeira linha e recusa o lote inteiro quando
  # as outras divergem, e os achados da triagem e os da leitura naturalmente
  # divergem: só a triagem sabe `waiting_since`. Normalizar aqui é o que impede
  # uma rodada de morrer por causa de uma chave a menos.
  def stamp(row)
    identity(row).merge(content(row)).merge(
      account_id: @account.id, scan_id: @scan.id,
      last_seen_at: @now, created_at: @now, updated_at: @now
    )
  end

  def identity(row)
    {
      conversation_id: row[:conversation_id], conversation_display_id: row[:conversation_display_id],
      contact_id: row[:contact_id], ai_assistant_id: row[:ai_assistant_id], case_key: row[:case_key]
    }
  end

  def content(row)
    {
      severity: row[:severity], detail: row[:detail], excerpt: row[:excerpt],
      author: row[:author], source: row[:source], occurred_at: row[:occurred_at],
      title: row[:title].presence || Ai::Manager::Conversations::Cases.title_for(row[:case_key]),
      value_cents_brl: row[:value_cents_brl].to_i, metadata: row[:metadata] || {},
      waiting_since: row[:waiting_since]
    }
  end

  def purge
    cutoff = @now - PURGE_AFTER
    Ai::Manager::ConversationFinding.where(account_id: @account.id)
                                    .where(occurred_at: (...cutoff))
                                    .delete_all
  end

  def finish(written)
    @scan.update!(
      status: 'done', finished_at: Time.current,
      conversations_scanned: triage.scanned, conversations_read: reader.read_count,
      findings_count: written, cost_cents_brl: reader.cost_cents_brl,
      summary: summary_for(written)
    )
  end

  # O que ficou de fora é tão importante quanto o que apareceu: sem o número de
  # candidatos, doze cartões parecem a operação inteira quando podem ser o teto
  # de leitura tendo cortado noventa conversas que ninguém olhou.
  def summary_for(written)
    {
      'candidates' => reader.candidate_count,
      'triage_findings' => triage.findings.length,
      'reading_findings' => reader.findings.length,
      'written' => written,
      'reading_skipped' => reader.skipped_reason,
      'window_start' => since.iso8601,
      'window_end' => @now.iso8601
    }.compact
  end

  def fail_scan(error)
    Rails.logger.error("[Athenas moderador] varredura falhou account=#{@account.id}: #{error.message}")
    ChatwootExceptionTracker.new(error, account: @account).capture_exception
    @scan.update(status: 'failed', finished_at: Time.current,
                 summary: { 'error' => error.message.to_s.truncate(300) })
  end
end
