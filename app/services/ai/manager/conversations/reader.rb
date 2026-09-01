# A camada paga: lê o que a triagem levantou e diz o que uma consulta não diz.
#
# "Cliente sem resposta há 31h" a triagem resolve de graça. "A cliente queria o
# Blond, perguntou o preço duas vezes e a conversa morreu" exige entender o que
# foi dito, e é só para isso que o modelo é chamado. Por isso o leitor NUNCA
# recebe a conta inteira: ele recebe a lista que a triagem já filtrou, cortada
# num teto, da mais urgente para a menos.
#
# Uma chamada por conversa, e não um lote com várias juntas. O lote sai mais
# barato e traz de volta o pior defeito possível nesta tela: o modelo atribui o
# achado de uma cliente à conversa de outra, o operador clica, abre um diálogo
# que não tem nada a ver, e não confia mais em nenhum cartão. O prefixo é
# idêntico entre as chamadas e fica em cache, então o desconto vem sem o risco.
#
# Nada aqui derruba a rodada. Uma conversa que falha na leitura é registrada e
# pulada: metade da leitura vale mais que nenhuma, e os achados da triagem já
# estão gravados de qualquer forma.
class Ai::Manager::Conversations::Reader
  Cases = Ai::Manager::Conversations::Cases
  Prompt = Ai::Manager::Conversations::ReadingPrompt

  # Teto de conversas lidas por rodada. O que ficou de fora aparece na tela em
  # número: uma varredura que corta em silêncio se apresenta como completa, e é
  # assim que um operador conclui que está tudo bem quando não está.
  MAX_READ = 60
  # Modelo barato de propósito. A tarefa é classificar um diálogo curto contra
  # um catálogo fechado, e não redigir: pagar por um modelo grande aqui compra
  # prosa melhor num campo que ninguém lê inteiro.
  #
  # O apelido e NÃO o id datado, e isto não é estilo. Ai::PricingCalculator casa
  # o modelo por chave exata e cai no preço do Sonnet quando não encontra, então
  # 'claude-haiku-4-5-20251001' faria cada leitura ser cobrada do operador a
  # quatro vezes o que ela custou de verdade. A chave da tabela é esta.
  MODEL = 'claude-haiku-4-5'.freeze
  MAX_TOKENS = 600
  # Zero porque a mesma conversa lida duas vezes tem que dar o mesmo resultado.
  # Um painel que muda de opinião entre duas rodadas sem nada ter mudado na
  # conversa é um painel que o operador para de levar a sério.
  TEMPERATURE = 0.0
  MAX_CASES = 2

  def initialize(account:, assistant:, details:, candidates:, waits: {}, limit: MAX_READ, now: Time.current)
    @account = account
    @assistant = assistant
    @details = details
    @candidates = Array(candidates)
    @waits = waits
    @limit = limit
    @now = now
    @cost_brl = 0.0
    @read = 0
  end

  def findings
    @findings ||= readable? ? scan : []
  end

  def read_count
    findings
    @read
  end

  def candidate_count
    @candidates.size
  end

  def cost_cents_brl
    findings
    (@cost_brl * 100).round
  end

  # Sem agente com chave configurada não há leitura, e isso não é um erro: a
  # aba continua útil só com a triagem, que é de graça. O motivo sobe para a
  # tela em vez de a rodada terminar com uma lista curta sem explicação.
  def skipped_reason
    return nil if readable?

    @assistant.nil? ? 'Nenhum agente de IA configurado nesta conta' : 'O agente está sem chave de API configurada'
  end

  private

  def readable?
    @assistant.present? && @assistant.resolved_anthropic_key.present?
  end

  def selected
    @selected ||= @candidates.first(@limit)
  end

  def transcripts
    @transcripts ||= Ai::Manager::Conversations::Transcripts.new(conversation_ids: selected).all
  end

  def scan
    selected.flat_map { |id| read_one(id) }.compact
  end

  def read_one(conversation_id)
    lines = transcripts[conversation_id]
    detail = @details.for(conversation_id)
    return [] if lines.blank? || detail.nil?

    @read += 1
    parse(ask(lines, detail), conversation_id, detail, lines)
  rescue StandardError => e
    Rails.logger.error("[Athenas moderador] leitura falhou account=#{@account.id} conversa=#{conversation_id}: #{e.message}")
    []
  end

  def ask(lines, detail)
    response = Ai::ClaudeService.new(assistant: @assistant, account: @account).chat(
      messages: [{ role: 'user', content: Prompt.user_message(
        lines, waited_hours: @waits[detail.conversation_id], contact: detail.contact_name
      ) }],
      system: Prompt.system,
      # `phase` próprio para o gasto da moderação não entrar no painel de ROI
      # como se fosse custo de atender cliente. São coisas diferentes e somá-las
      # faria o agente parecer mais caro do que é.
      phase: 'moderation',
      model: MODEL, max_tokens: MAX_TOKENS, temperature: TEMPERATURE
    )
    @cost_brl += response[:invocation]&.cost_brl.to_f
    response[:content]
  end

  # Modelo que devolve chave fora do catálogo, motivo vazio ou caso repetido é
  # descartado aqui. A tela não sabe rotular uma categoria inventada, e o
  # operador leria um cartão sem nome.
  def parse(content, conversation_id, detail, lines)
    cases = extract(content)
    cases.filter_map { |item| build(item, conversation_id, detail, lines) }
         .uniq { |finding| finding[:case_key] }
         .first(MAX_CASES)
  end

  def extract(content)
    json = content.to_s[/\{.*\}/m]
    return [] if json.blank?

    parsed = JSON.parse(json)
    parsed['casos'].is_a?(Array) ? parsed['casos'].grep(Hash) : []
  rescue JSON::ParserError
    []
  end

  def build(item, conversation_id, detail, lines)
    key = item['chave'].to_s
    reason = item['motivo'].to_s.strip
    return nil unless Cases::READING_KEYS.include?(key) && reason.present?

    {
      conversation_id: conversation_id, conversation_display_id: detail.display_id,
      contact_id: detail.contact_id, ai_assistant_id: detail.assistant_id,
      case_key: key, severity: Cases.severity_for(key), title: Cases.title_for(key),
      detail: reason.truncate(400), author: detail.author, source: 'reading',
      value_cents_brl: detail.value_cents, occurred_at: occurred_at(lines),
      **quote(item['trecho'], detail, lines)
    }
  end

  # O cartão nunca mostra frase que o cliente não escreveu.
  #
  # O modelo é instruído a copiar literalmente, e quase sempre copia. Quando não
  # copia, a saída não é confiar na paráfrase dele: é trocar pelo texto real da
  # última mensagem do cliente e deixar registrado que a citação não conferiu.
  # Assim o achado sobrevive, e nenhuma aspa falsa entra na tela.
  def quote(claimed, detail, lines)
    text = claimed.to_s.strip
    said = lines.select(&:incoming).map(&:text).join("\n")
    return { excerpt: text, metadata: { 'excerpt_verified' => true } } if text.present? && said.include?(text)

    { excerpt: detail.excerpt, metadata: { 'excerpt_verified' => false } }
  end

  def occurred_at(lines)
    lines.select(&:incoming).map(&:at).compact.max || lines.map(&:at).compact.max || @now
  end
end
