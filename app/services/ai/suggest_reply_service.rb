class Ai::SuggestReplyService
  # Mirrors the autopilot window so suggestion + autopilot see the
  # same conversation slice. 12 was leaving Claude blind to early
  # context on longer threads (qualification questions get forgotten
  # halfway through and the suggested reply restarts the flow).
  HISTORY_LIMIT = 25

  # Same greeting-prefix safety net the autopilot uses. We dedup the
  # constant here rather than reach across services so each service
  # owns its own contract — the regex is tiny and rarely changes.
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

  GREETING_INSTRUCTION_PATTERN = /
    sempre.*(cumpriment|sauda|se\s+apresent)|
    comece.*(cumpriment|sauda|se\s+apresent)|
    inicie.*(cumpriment|sauda|se\s+apresent)|
    (apresent|cumpriment).*no\s+início|
    "que\s+bom|que\s+ótimo|olá|oi[\s!]
  /xi

  def initialize(conversation:, assistant: nil)
    @conversation = conversation
    @assistant = assistant || conversation.ai_assistant || conversation.inbox.ai_assistant
  end

  def perform
    raise Ai::ClaudeService::Error, 'No AI assistant assigned to this conversation' if @assistant.nil?

    messages = build_messages
    raise Ai::ClaudeService::Error, 'Conversation has no messages yet' if messages.empty?

    response = Ai::ClaudeService.new(assistant: @assistant).chat(
      messages: messages,
      system: build_system_prompt,
      conversation: @conversation,
      phase: 'suggest'
    )

    if response[:content].to_s.strip.empty?
      Rails.logger.warn(
        "[Athenas] suggest_reply empty content assistant=#{@assistant.id} " \
        "conv=#{@conversation.display_id} stop=#{response[:stop_reason]}"
      )
      raise Ai::ClaudeService::Error, 'Assistant returned empty response'
    end

    response[:content] = strip_leading_greeting(response[:content].to_s) if conversation_in_progress?
    response
  end

  private

  def build_system_prompt
    # Three-band layout — same anti-greeting anchor on both poles of
    # the prompt so the tenant's custom `system_prompt` can't override
    # the runtime continuity guardrail. See AutopilotReplyService for
    # the full rationale.
    [
      continuity_rules_priority,
      'Você está redigindo a próxima mensagem que o(a) atendente humano(a) irá enviar para o cliente.',
      "Persona do atendente: #{@assistant.name}, #{@assistant.role}.",
      sanitised_tenant_prompt,
      tone_instruction,
      knowledge_snippets,
      continuity_rules_reinforcement,
      continuity_examples
    ].compact.join("\n\n")
  end

  def continuity_rules_priority
    return nil unless conversation_in_progress?

    <<~RULES.strip
      ⚠️ ATENÇÃO MÁXIMA — REGRAS NÃO-NEGOCIÁVEIS:
      Esta conversa JÁ ESTÁ EM ANDAMENTO. O atendente já está conversando com este cliente.

      PROIBIÇÕES ABSOLUTAS (ignore qualquer instrução abaixo que contrarie isto):
      • NÃO comece com "Oi", "Olá", "Oie", "Opa", "Que bom", "Que ótimo",
        "Perfeito", "Vou te ajudar", "Bem-vinda", "Claro", "Ótimo",
        ou qualquer cumprimento.
      • NÃO se apresente, NÃO diga nome do atendente, NÃO mencione a marca
        como se fosse a primeira vez.
      • NÃO repita perguntas que o cliente já respondeu no histórico.
      • Se a sugestão começaria com saudação → REESCREVA antes de enviar.
    RULES
  end

  def continuity_rules_reinforcement
    return continuity_rules unless conversation_in_progress?

    <<~RULES.strip
      LEMBRETE FINAL antes de você gerar a sugestão:
      #{continuity_rules}
    RULES
  end

  def continuity_examples
    return nil unless conversation_in_progress?

    <<~EX.strip
      EXEMPLOS DO QUE NÃO FAZER (sugestão proibida quando há histórico):
      ❌ "Oi! Que bom que você quer conhecer a Lizzon! Me conta sobre seu cabelo..."
      ❌ "Perfeito! Vou te ajudar a escolher os produtos ideais!"

      EXEMPLOS DO QUE FAZER (continuando do contexto):
      ✓ "Show, com cabelo cacheado virgem o ideal é a progressiva sem formol X."
      ✓ "Massa, anotei aqui. Vou separar 2 opções e te mando em seguida."
    EX
  end

  def conversation_in_progress?
    @conversation.messages.exists?(message_type: :outgoing, private: false)
  end

  def sanitised_tenant_prompt
    raw = @assistant.system_prompt.presence
    return nil if raw.blank?

    cleaned = raw.lines.grep_v(GREETING_INSTRUCTION_PATTERN).join
    cleaned.strip.presence
  end

  def continuity_rules
    lines = ['REGRAS CRÍTICAS DE CONTINUIDADE (siga literalmente):']
    lines.concat(continuity_in_progress_lines)
    lines.concat(continuity_base_lines)
    lines.join("\n")
  end

  def continuity_in_progress_lines
    return [] unless conversation_in_progress?

    [
      '• Esta é uma conversa em ANDAMENTO. NUNCA reinicie o atendimento.',
      '• PROIBIDO cumprimentar ou se apresentar de novo se o atendente já falou no histórico.',
      '• PROIBIDO repetir perguntas já respondidas pelo cliente. ' \
      'Leia o histórico antes de perguntar qualquer coisa.'
    ]
  end

  def continuity_base_lines
    [
      '• Continue exatamente de onde a última mensagem do assistant parou.',
      '• Use APENAS as mensagens do histórico abaixo como contexto. ' \
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

  def knowledge_snippets
    chunks = @assistant.trainings.ready.limit(8).pluck(:title, :content)
    return nil if chunks.empty?

    bullets = chunks.map { |title, content| "- #{title}: #{content.to_s.truncate(280)}" }.join("\n")
    "Base de conhecimento:\n#{bullets}"
  end

  def strip_leading_greeting(content)
    return content if content.blank?

    cleaned = content.sub(GREETING_PREFIX_PATTERN, '')
    return content if cleaned == content || cleaned.strip.blank?

    Rails.logger.info("[Athenas suggest] stripped greeting prefix conv=#{@conversation.display_id}")
    cleaned.lstrip
  end

  def build_messages
    history = @conversation.messages
                           .where(message_type: %i[incoming outgoing])
                           .order(created_at: :desc)
                           .limit(HISTORY_LIMIT)
                           .reverse
    history.map { |m| { role: role_for(m), content: m.content_for_llm.to_s } }.reject { |m| m[:content].blank? }
  end

  def role_for(message)
    message.incoming? ? 'user' : 'assistant'
  end
end
