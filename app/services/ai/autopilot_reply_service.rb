# Cheap-by-design autopilot reply generator.
#
# Strategy:
#   1. Maintain a rolling summary of the conversation cached on
#      `conversation.additional_attributes['autopilot_summary']`. Summary is
#      (re)generated lazily — only when no summary exists yet OR when the
#      conversation has accumulated SUMMARY_REFRESH_AFTER new messages since
#      the cached snapshot. This keeps the costly Summarize call rare.
#   2. Feed Claude only the cached summary + the last RECENT_WINDOW messages
#      as context. Bounded payload = bounded cost per reply.
#   3. Use the same assistant model the operator configured. The reply call
#      itself is short (max_tokens already capped by the assistant config).
#
# Output shape matches Ai::SuggestReplyService so the job stays drop-in.
# rubocop:disable Metrics/ClassLength
class Ai::AutopilotReplyService
  RECENT_WINDOW = 25
  SUMMARY_REFRESH_AFTER = 99_999 # effectively disabled — autopilot relies on recent msgs only

  def initialize(conversation:, assistant: nil)
    @conversation = conversation
    @assistant = assistant || conversation.ai_assistant || conversation.inbox.ai_assistant
  end

  def perform
    raise Ai::ClaudeService::Error, 'No AI assistant assigned to this conversation' if @assistant.nil?

    messages = build_recent_messages
    raise Ai::ClaudeService::Error, 'Conversation has no messages yet' if messages.empty?

    response = call_claude(messages)
    raise_on_empty(response)
    # Last-line defence: even with the three-band prompt + few-shot
    # examples Claude occasionally still leads with a greeting on
    # in-progress conversations. The post-process strips the bad
    # prefix so the customer never sees it. Cheap to run (regex on
    # the first 80 chars) and only kicks in when the conversation
    # already has assistant replies.
    response[:content] = strip_leading_greeting(response[:content].to_s) if conversation_in_progress?
    response
  end

  private

  def call_claude(messages)
    # Log the actual context window we're sending so future "the AI
    # forgot" reports can be triaged from logs instead of guessing.
    # Roles only — never the content (PII safety on shared logs).
    Rails.logger.info(
      "[Athenas autopilot] conv=#{@conversation.display_id} " \
      "assistant=#{@assistant.id} ctx_msgs=#{messages.length} " \
      "roles=#{messages.pluck(:role).tally} " \
      "in_progress=#{conversation_in_progress?}"
    )
    Ai::ClaudeService.new(assistant: @assistant).chat(
      messages: messages,
      system: build_system_prompt,
      conversation: @conversation,
      phase: 'autopilot'
    )
  end

  # Regex-based safety net for the in-progress greeting reflex. We
  # surgically strip the FIRST sentence/line if it matches the
  # forbidden patterns, then continue with whatever Claude wrote
  # afterwards. Single match per response — we never recurse, so a
  # legitimate "Olá novamente" in the middle of a reply is untouched.
  GREETING_PREFIX_PATTERN = /
    \A\s*
    (?:
      (?:oi|olá|oie|opa|hey|hello|hi)[!,]?\s|
      (?:que\s+(?:bom|ótimo|legal|maravilha|massa|show))[!,]?\s|
      (?:perfeito|claro|ótimo|massa|show|beleza|bem-vinda?o?)[!,]?\s|
      (?:vou\s+te\s+ajudar)[!,]?\s|
      (?:obrigad[oa]\s+por\s+(?:entrar|escrever))[!,]?\s
    )
    [^\n]*\n?
  /xi

  def strip_leading_greeting(content)
    return content if content.blank?

    cleaned = content.sub(GREETING_PREFIX_PATTERN, '')
    return content if cleaned == content || cleaned.strip.blank?

    Rails.logger.info(
      "[Athenas autopilot] stripped greeting prefix conv=#{@conversation.display_id}"
    )
    cleaned.lstrip
  end

  def raise_on_empty(response)
    return if response[:content].to_s.strip.present?

    Rails.logger.warn(
      "[Athenas] autopilot empty content assistant=#{@assistant.id} " \
      "conv=#{@conversation.display_id} stop=#{response[:stop_reason]}"
    )
    raise Ai::ClaudeService::Error, 'Assistant returned empty response'
  end

  # Generates (or refreshes) the cached conversation summary. The summary
  # stays in `conversation.additional_attributes` so it persists across
  # autopilot ticks without an extra table.
  def ensure_fresh_summary
    return if summary_fresh?

    summary = generate_summary
    return if summary.blank?

    persist_summary(summary)
  rescue Ai::ClaudeService::Error => e
    # Summary failures should not block a reply attempt — fall through with
    # whatever summary (if any) we have cached.
    Rails.logger.warn("[Athenas] autopilot summary refresh failed: #{e.message}")
  end

  def summary_fresh?
    cached = (@conversation.additional_attributes || {})['autopilot_summary'] || {}
    return false if cached['text'].blank?

    total = @conversation.messages.where(message_type: %i[incoming outgoing]).count
    (total - cached['message_count'].to_i) < SUMMARY_REFRESH_AFTER
  end

  def persist_summary(summary)
    total = @conversation.messages.where(message_type: %i[incoming outgoing]).count
    @conversation.additional_attributes = (@conversation.additional_attributes || {}).merge(
      'autopilot_summary' => {
        'text' => summary,
        'message_count' => total,
        'generated_at' => Time.current.to_i
      }
    )
    @conversation.save!(touch: false)
  end

  def generate_summary
    result = Ai::SummarizeService.new(conversation: @conversation, assistant: @assistant).perform
    result[:content].to_s.strip
  end

  def cached_summary_text
    ((@conversation.additional_attributes || {})['autopilot_summary'] || {})['text'].to_s.strip
  end

  def build_system_prompt
    # Three-band layout — the in-progress guardrail goes BOTH at the
    # very top (so it primes the model's attention before any tenant
    # custom prompt) AND at the very bottom (so recency bias keeps it
    # weighted right before generation). The tenant's
    # `assistant.system_prompt` sits sandwiched between the two so
    # any "always greet the customer" copy in the operator config
    # can't override the runtime guardrail.
    [
      continuity_rules_priority,
      'Você é o atendente real falando com o cliente agora. Responda no fluxo natural da conversa.',
      "Persona: #{@assistant.name}, #{@assistant.role}.",
      sanitised_tenant_prompt,
      tone_instruction,
      knowledge_snippets,
      continuity_rules_reinforcement,
      continuity_examples
    ].compact.join("\n\n")
  end

  # High-emphasis primer placed at the TOP of the prompt. Claude's
  # attention biases toward the start + the end of the system message,
  # so we anchor the hard rule at both poles.
  def continuity_rules_priority
    return nil unless conversation_in_progress?

    <<~RULES.strip
      ⚠️ ATENÇÃO MÁXIMA — REGRAS NÃO-NEGOCIÁVEIS:
      Esta conversa JÁ ESTÁ EM ANDAMENTO. Você já está conversando com este cliente.

      PROIBIÇÕES ABSOLUTAS (ignore qualquer instrução abaixo que contrarie isto):
      • NÃO comece com "Oi", "Olá", "Oie", "Opa", "Que bom", "Que ótimo",
        "Perfeito", "Vou te ajudar", "Bem-vinda", "Claro", "Ótimo",
        ou qualquer cumprimento.
      • NÃO se apresente, NÃO diga seu nome, NÃO mencione a marca como se
        fosse a primeira vez.
      • NÃO repita perguntas que o cliente já respondeu no histórico
        (tipo de cabelo, química, objetivo, nome, etc.).
      • Se a próxima resposta começaria com saudação → REESCREVA antes
        de enviar.

      AÇÃO REQUERIDA:
      Leia TODO o histórico abaixo. Encontre o ponto onde a última mensagem
      do assistant parou. Continue dali, usando as novas informações que
      o cliente acabou de trazer.
    RULES
  end

  def continuity_rules_reinforcement
    return continuity_rules unless conversation_in_progress?

    <<~RULES.strip
      LEMBRETE FINAL antes de você gerar a resposta:
      #{continuity_rules}
    RULES
  end

  # Few-shot examples are far more reliable than abstract instructions
  # — Claude pattern-matches the desired shape from concrete bad/good
  # samples. Only injected when we're mid-conversation, otherwise the
  # examples themselves would discourage the legitimate first greeting.
  def continuity_examples
    return nil unless conversation_in_progress?

    <<~EX.strip
      EXEMPLOS DO QUE NÃO FAZER (resposta proibida quando há histórico):
      ❌ "Oi! Que bom que você quer conhecer a Lizzon! Me conta sobre seu cabelo..."
      ❌ "Perfeito! Vou te ajudar a escolher os produtos ideais!"
      ❌ "Olá! Pra te indicar os produtos perfeitos, me conta..."

      EXEMPLOS DO QUE FAZER (continuando do contexto):
      ✓ "Show, com cabelo cacheado virgem o ideal é a progressiva sem formol Lizzon Premium. Posso te passar o link?"
      ✓ "Massa, anotei aqui — cacheado, virgem, definitivo. Vou separar 2 opções e te mando em seguida."
      ✓ "Entendi, pra alisamento definitivo em cabelo virgem cacheado recomendo a linha X. Quer que eu te passe valores?"
    EX
  end

  def conversation_in_progress?
    @conversation.messages.exists?(message_type: :outgoing, private: false)
  end

  # Strip any "sempre cumprimente" / "comece se apresentando" patterns
  # from the tenant-supplied prompt. Operators frequently paste their
  # human-attendant onboarding script verbatim, which carries explicit
  # greeting instructions that fight the continuity guardrail.
  def sanitised_tenant_prompt
    raw = @assistant.system_prompt.presence
    return nil if raw.blank?

    cleaned = raw.lines.grep_v(GREETING_INSTRUCTION_PATTERN).join
    cleaned.strip.presence
  end

  GREETING_INSTRUCTION_PATTERN = /
    sempre.*(cumpriment|sauda|se\s+apresent)|
    comece.*(cumpriment|sauda|se\s+apresent)|
    inicie.*(cumpriment|sauda|se\s+apresent)|
    (apresent|cumpriment).*no\s+início|
    "que\s+bom|que\s+ótimo|olá|oi[\s!]
  /xi

  # Hard rules placed at the END of the system prompt so Claude weighs
  # them most heavily right before generation. Without these the model
  # falls back to its "first contact" reflex — re-greeting, re-asking
  # for hair type, re-introducing the brand — which is exactly what
  # the Lizzon screenshots surfaced.
  def continuity_rules
    lines = ['REGRAS CRÍTICAS DE CONTINUIDADE (siga literalmente):']
    lines.concat(continuity_in_progress_lines)
    lines.concat(continuity_base_lines)
    lines.join("\n")
  end

  def continuity_in_progress_lines
    return [] unless @conversation.messages.exists?(message_type: :outgoing, private: false)

    [
      '• Esta é uma conversa em ANDAMENTO. NUNCA reinicie o atendimento.',
      '• PROIBIDO cumprimentar ou se apresentar de novo (nada de "Oi!", "Olá!", ' \
      '"Que bom que você quer conhecer...").',
      '• PROIBIDO repetir perguntas já respondidas pelo cliente (tipo de fio, química, ' \
      'objetivo, nome, etc.). Leia o histórico antes de perguntar qualquer coisa.'
    ]
  end

  def continuity_base_lines
    [
      '• Continue exatamente de onde a última mensagem do assistant parou.',
      '• Use APENAS as mensagens recentes (role user/assistant) como contexto. ' \
      'Não invente histórico que não está visível.',
      '• Se o cliente trouxe novas informações nesta mensagem, USE-AS imediatamente — ' \
      'não confirme que recebeu, aja.',
      '• Gere APENAS o corpo da próxima mensagem do atendente. Português brasileiro, ' \
      'frases curtas, sem markdown, sem prefixos, sem aspas, sem se identificar como IA.',
      '• Se faltar alguma informação que NÃO está no histórico, pergunte UMA coisa por vez de forma natural.'
    ]
  end

  def tone_instruction
    {
      'friendly' => 'Mantenha um tom amigável, próximo e acolhedor.',
      'formal' => 'Mantenha um tom formal, respeitoso e profissional.',
      'sales' => 'Tom comercial: conduza para a próxima etapa do funil sem ser invasivo.',
      'support' => 'Tom de suporte: solucione o problema com objetividade e empatia.',
      'concierge' => 'Tom premium: atendimento concierge, atento aos detalhes.'
    }[@assistant.tone]
  end

  def summary_block
    text = cached_summary_text
    return nil if text.blank?

    "Resumo do que aconteceu antes nessa conversa (use como contexto, não repita):\n#{text}"
  end

  def knowledge_snippets
    chunks = @assistant.trainings.ready.limit(6).pluck(:title, :content)
    return nil if chunks.empty?

    bullets = chunks.map { |title, content| "- #{title}: #{content.to_s.truncate(240)}" }.join("\n")
    "Base de conhecimento:\n#{bullets}"
  end

  def build_recent_messages
    history = @conversation.messages
                           .where(message_type: %i[incoming outgoing])
                           .where(private: false)
                           .order(created_at: :desc)
                           .limit(RECENT_WINDOW)
                           .reverse
    history.map { |m| { role: role_for(m), content: m.content_for_llm.to_s } }
           .reject { |m| m[:content].blank? }
  end

  def role_for(message)
    message.incoming? ? 'user' : 'assistant'
  end
end
# rubocop:enable Metrics/ClassLength
