# O Guia consultando o sistema, em vez de só recitar o manual.
#
# Segue o contrato de Ai::Agent::CompositeExecutor — `definitions` e
# `call(name, input)` devolvendo String — o mesmo de Ai::Calendar::SchedulingTools
# e do belezaki. Nada aqui reescreve consulta: cada ferramenta chama o serviço
# que a tela já usa.
#
# ## Por que ferramenta e não contexto no prompt
#
# "Responder sobre tudo" e "não explodir o input" só convivem assim. Despejar o
# estado da conta no prompt faria toda pergunta — inclusive "o que é o Chatflow"
# — carregar a fila, as caixas e o relatório junto. Com ferramenta o dado só
# viaja quando o modelo pede, e quem pergunta sobre o manual não paga por nada
# disso.
#
# ## Ler é de graça, analisar custa
#
# Três destas ferramentas são consulta agregada e cabem em poucas centenas de
# caracteres. A quarta dispara uma varredura que chama modelo UMA VEZ POR
# CONVERSA, e por isso só existe para administrador e só depois de a pessoa
# confirmar. O padrão é o mesmo do agendamento: o modelo não gasta o dinheiro do
# operador porque achou que seria útil.
class Ai::Wiki::Tools
  # Um cartão já é o bastante para o Guia dizer o que está pegando. A tela mostra
  # até 200; despejar isso aqui seria trocar a resposta por um relatório.
  FINDINGS_SHOWN = 5
  # Depois disso a leitura não descreve mais o atendimento de hoje, e o Guia tem
  # que dizer a data em vez de responder como se fosse agora.
  STALE_AFTER_HOURS = 24

  def self.definitions(can_scan:)
    Ai::Wiki::ToolDefinitions.all(can_scan: can_scan)
  end

  def initialize(account:, user: nil)
    @account = account
    @user = user
  end

  def definitions
    self.class.definitions(can_scan: can_scan?)
  end

  # Marcado ANTES da chamada, como no executor de tool custom: disparada a
  # varredura, o turno deixou de ser repetível mesmo que algo estoure depois.
  def performed_write?
    @performed_write.present?
  end

  def call(name, input)
    case name
    when 'fila_de_conversas' then queue
    when 'analise_das_conversas' then findings
    when 'estado_das_caixas' then inboxes
    when 'rodar_analise' then run_scan(input)
    else { erro: "ferramenta desconhecida: #{name}" }.to_json
    end
  rescue StandardError => e
    Rails.logger.error("[Guia] ferramenta #{name} falhou account=#{@account.id}: #{e.message}")
    # Dado e não exceção: o loop segue e o modelo conta o que houve, em vez de a
    # pessoa receber uma tela de erro por causa de uma consulta.
    { erro: 'não consegui consultar isso agora' }.to_json
  end

  private

  # Só administrador gasta crédito, a mesma regra que o botão da tela aplica.
  def can_scan?
    @user.present? && @account.account_users.find_by(user_id: @user.id)&.administrator?
  end

  # Os mesmos quatro números do painel ao vivo, sobre o mesmo conjunto: fora o
  # sandbox do playground e fora os grupos, senão a conta se vê maior do que é.
  def queue
    scope = @account.conversations.not_sandbox.non_groups
    open = scope.open
    {
      abertas: open.count,
      sem_primeira_resposta: open.unattended.count,
      sem_responsavel: open.unassigned.count,
      pendentes: scope.pending.count
    }.to_json
  end

  def findings
    listing = Ai::Manager::Conversations::Listing.new(account: @account, days: 7).payload
    scan = listing[:last_scan]
    return { analise_nunca_rodou: true }.to_json if scan.blank?

    ran_at = scan[:finished_at] || scan[:started_at]
    {
      rodou_em: ran_at&.iso8601,
      analise_desatualizada: stale?(ran_at),
      total: listing.dig(:counts, :total),
      por_gravidade: listing.dig(:counts, :by_severity),
      casos: Array(listing[:findings]).first(FINDINGS_SHOWN).map { |card| card_line(card) }
    }.to_json
  end

  # Sem data não dá para afirmar que está fresca, e afirmar isso é o erro caro:
  # o Guia responderia sobre o atendimento de hoje lendo a leitura da semana
  # passada, sem avisar ninguém.
  def stale?(ran_at)
    ran_at.blank? || ran_at < STALE_AFTER_HOURS.hours.ago
  end

  # Só o que o Guia precisa para falar do caso. O cartão inteiro carrega trecho
  # da conversa, contato e metadados que nada acrescentam a uma frase.
  def card_line(card)
    { caso: card[:title] || card[:case_key], gravidade: card[:severity],
      conversa: card[:conversation_display_id] }.compact
  end

  def inboxes
    rows = @account.inboxes.map do |inbox|
      { nome: inbox.name, canal: inbox.channel_type.to_s.demodulize,
        precisa_reconectar: reconnect?(inbox) }
    end
    { caixas: rows }.to_json
  end

  def reconnect?(inbox)
    channel = inbox.channel
    channel.respond_to?(:reauthorization_required?) && channel.reauthorization_required?
  rescue StandardError
    # O estado de reconexão mora no Redis. Ele fora do ar não pode transformar
    # "quantas caixas eu tenho" numa falha.
    nil
  end

  def run_scan(input)
    return { erro: 'só administrador pode rodar a análise' }.to_json unless can_scan?

    running = @account.ai_manager_conversation_scans.find_by(status: 'running')
    return { ja_rodando: true, janela_horas: running.window_hours }.to_json if running

    @performed_write = true
    janela = Ai::Manager::ConversationScan.window_for(input['janela_horas'] || input[:janela_horas])
    scan = @account.ai_manager_conversation_scans.create!(window_hours: janela, user_id: @user.id)
    Ai::Manager::ConversationScanJob.perform_later(scan.id)

    { analise_iniciada: true, janela_horas: janela,
      aviso: 'a leitura roda em segundo plano e aparece na aba Conversas do Gerente' }.to_json
  end
end
