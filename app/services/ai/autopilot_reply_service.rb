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
  # Raised when a generated reply would repeat a recent assistant turn even
  # after a forced regeneration. The job rescues this and stays silent so a
  # human can take over instead of the bot spamming the same questions.
  class LoopSuppressed < StandardError; end

  # Bigger window so customer answers from earlier in the conversation
  # (hair type, química, objetivo) stay in Claude's view instead of
  # rolling off after a 25-message burst. The summary block below
  # carries forward anything older than this window.
  RECENT_WINDOW = 60
  # Refresh the rolling summary every 20 new messages past the cache.
  # Small enough that long conversations don't drift, large enough that
  # we're not paying for a Summarize call on every autopilot tick.
  SUMMARY_REFRESH_AFTER = 20
  # Deterministic loop-breaker. Soft prompt rules ("não repita perguntas")
  # are routinely ignored when a tenant training doc carries a verbatim
  # qualification script — Claude treats the script as authoritative and
  # re-recites it every turn. We compare each candidate reply against the
  # recent assistant messages and, on a near-duplicate, regenerate ONCE
  # with a hard override; if it still loops we stay silent rather than
  # spam the customer with the same questions.
  LOOP_SIMILARITY_THRESHOLD = 0.6
  LOOP_LOOKBACK = 4

  def initialize(conversation:, assistant: nil)
    @conversation = conversation
    @assistant = assistant || conversation.ai_assistant || conversation.inbox.ai_assistant
  end

  def perform
    raise Ai::ClaudeService::Error, 'No AI assistant assigned to this conversation' if @assistant.nil?

    messages = build_recent_messages
    raise Ai::ClaudeService::Error, 'Conversation has no messages yet' if messages.empty?

    # Refresh the cached summary BEFORE building the system prompt so
    # `summary_block` reflects the latest state. `ensure_fresh_summary`
    # short-circuits when the cache is still fresh, so this is a no-op
    # on most ticks.
    ensure_fresh_summary

    response = call_claude(messages)
    raise_on_empty(response)
    # Last-line defence: even with the three-band prompt + few-shot
    # examples Claude occasionally still leads with a greeting on
    # in-progress conversations. The post-process strips the bad
    # prefix so the customer never sees it. Cheap to run (regex on
    # the first 80 chars) and only kicks in when the conversation
    # already has assistant replies.
    response[:content] = strip_leading_greeting(response[:content].to_s) if conversation_in_progress?

    # Deterministic loop-breaker (see LOOP_SIMILARITY_THRESHOLD). When the
    # candidate echoes a recent assistant turn we retry once with a hard
    # override, then suppress if it still loops.
    break_loop_if_needed(messages, response)
  end

  private

  # Returns the response untouched when it isn't a near-duplicate of a
  # recent assistant turn. Otherwise regenerates ONCE with an escalated
  # override band; if that still loops, raises a LoopSuppressed error so
  # the job stays silent instead of re-sending the same questions.
  def break_loop_if_needed(messages, response)
    duplicated = matching_recent_reply(response[:content])
    return response if duplicated.nil?

    Rails.logger.warn(
      "[Athenas autopilot] loop detected conv=#{@conversation.display_id} " \
      "assistant=#{@assistant.id} — regenerating with override"
    )

    retry_response = call_claude(messages, override: loop_override_directive(duplicated))
    retry_response[:content] = strip_leading_greeting(retry_response[:content].to_s) if conversation_in_progress?

    if matching_recent_reply(retry_response[:content])
      Rails.logger.warn(
        "[Athenas autopilot] loop persists after override conv=#{@conversation.display_id} " \
        "assistant=#{@assistant.id} — suppressing reply (handing off to human)"
      )
      raise LoopSuppressed, "autopilot loop suppressed conv=#{@conversation.display_id}"
    end

    retry_response
  end

  # Compares the candidate against the last LOOP_LOOKBACK assistant
  # messages using token-set Jaccard similarity. Returns the first
  # recent message that crosses the threshold, or nil.
  def matching_recent_reply(candidate)
    candidate_tokens = token_set(candidate)
    return nil if candidate_tokens.size < 3

    recent_assistant_contents.find do |prior|
      jaccard(candidate_tokens, token_set(prior)) >= LOOP_SIMILARITY_THRESHOLD
    end
  end

  def recent_assistant_contents
    @conversation.messages
                 .where(message_type: :outgoing, private: false)
                 .order(created_at: :desc)
                 .limit(LOOP_LOOKBACK)
                 .pluck(:content)
                 .compact
  end

  def token_set(text)
    text.to_s.downcase.gsub(/[^\p{Alnum}\s]/u, ' ').split.reject { |t| t.length < 3 }.to_set
  end

  def jaccard(set_a, set_b)
    return 0.0 if set_a.empty? || set_b.empty?

    intersection = (set_a & set_b).size.to_f
    union = (set_a | set_b).size
    union.zero? ? 0.0 : (intersection / union)
  end

  def loop_override_directive(duplicated)
    <<~OVERRIDE.strip
      🚨 STOP — VOCÊ ACABOU DE GERAR UMA RESPOSTA REPETIDA.
      Você JÁ ENVIOU esta mensagem antes nesta conversa:
      «#{duplicated.to_s.truncate(280)}»

      É TERMINANTEMENTE PROIBIDO repetir essas perguntas ou esse texto.
      O cliente JÁ respondeu tudo isso. Olhe a MEMÓRIA DA CONVERSA acima.
      AÇÃO OBRIGATÓRIA AGORA: avance a venda — recomende o produto certo
      com base no que já se sabe e conduza para link/valor/fechamento.
      NÃO faça nenhuma pergunta de qualificação. NÃO cumprimente.
    OVERRIDE
  end

  def call_claude(messages, override: nil)
    # Log the actual context window we're sending so future "the AI
    # forgot" reports can be triaged from logs instead of guessing.
    # Roles only — never the content (PII safety on shared logs).
    # `summary_chars` is a proxy for "did the memory block get loaded?"
    # — 0 means the conversation rolled off the window without a cached
    # summary, which is exactly the failure mode that surfaced as
    # "Lizzon keeps re-asking the same questions".
    Rails.logger.info(
      "[Athenas autopilot] conv=#{@conversation.display_id} " \
      "assistant=#{@assistant.id} ctx_msgs=#{messages.length} " \
      "roles=#{messages.pluck(:role).tally} " \
      "in_progress=#{conversation_in_progress?} " \
      "summary_chars=#{cached_summary_text.length} " \
      "window=#{RECENT_WINDOW}"
    )
    Ai::ClaudeService.new(assistant: @assistant).chat(
      messages: messages,
      system: build_system_prompt(override: override),
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

    total = @conversation.messages.where(message_type: %i[incoming outgoing]).count
    Rails.logger.info(
      "[Athenas autopilot] summary refresh conv=#{@conversation.display_id} " \
      "assistant=#{@assistant.id} total_msgs=#{total}"
    )
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

  def build_system_prompt(override: nil)
    # Three-band layout — the in-progress guardrail goes BOTH at the
    # very top (so it primes the model's attention before any tenant
    # custom prompt) AND at the very bottom (so recency bias keeps it
    # weighted right before generation). The tenant's
    # `assistant.system_prompt` sits sandwiched between the two so
    # any "always greet the customer" copy in the operator config
    # can't override the runtime guardrail.
    # Summary FIRST (right after the hard guardrail) so the structured
    # FATOS DO CLIENTE block primes Claude's attention before persona /
    # tone / tenant prompt. Without this, the model sees pages of
    # operator instructions and treats the conversation as a cold start,
    # re-asking the same questions the customer already answered.
    [
      override,
      continuity_rules_priority,
      summary_block,
      'Você é o atendente real falando com o cliente agora. Responda no fluxo natural da conversa.',
      "Persona: #{@assistant.name}, #{@assistant.role}.",
      sanitised_tenant_prompt,
      tone_instruction,
      knowledge_snippets,
      continuity_rules_reinforcement,
      continuity_examples,
      override
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
      # The core anti-loop rule. The qualification reflex (re-asking hair
      # type / chemistry / goal) is what made Lizzon loop even with correct
      # memory. Forbid re-asking anything already known and force forward
      # progress toward the recommendation/sale.
      '• NUNCA repita perguntas de diagnóstico/qualificação (tipo de fio, química, ' \
      'objetivo, nome) cuja resposta já apareça no histórico OU na MEMÓRIA DA CONVERSA. ' \
      'Se o dado já existe, NÃO pergunte de novo — AVANCE: recomende o produto e conduza à compra.',
      '• Se o cliente já disse o que quer comprar, NÃO reinicie qualificação: confirme ' \
      'o produto e siga para link/valor/fechamento.',
      '• Gere APENAS o corpo da próxima mensagem do atendente. Português brasileiro, ' \
      'frases curtas, sem markdown, sem prefixos, sem aspas, sem se identificar como IA.',
      '• Se faltar UMA informação essencial que NÃO está no histórico nem na memória, ' \
      'pergunte só ela, uma vez, de forma natural.'
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

    # The summarize service is instructed to output a structured block
    # (FATOS DO CLIENTE / MOTIVO DO CONTATO / ESTADO ATUAL). We just add
    # a hard-emphasis header so Claude treats this as authoritative
    # memory — anything here is something the customer ALREADY shared
    # and must NOT be re-asked.
    <<~SUMMARY.strip
      📌 MEMÓRIA DA CONVERSA (use como base — NUNCA pergunte de novo o que está aqui):
      #{text}
    SUMMARY
  end

  def knowledge_snippets
    chunks = @assistant.trainings.ready.limit(6).pluck(:title, :content)
    return nil if chunks.empty?

    bullets = chunks.map { |title, content| "- #{title}: #{content.to_s.truncate(240)}" }.join("\n")
    # The knowledge base is REFERENCE, not a script. Operators often store a
    # qualification playbook ("ask hair type, chemistry, goal") in a training
    # doc; without this framing Claude recites it every turn and loops,
    # re-asking what the customer already answered. Anchor it as lookup
    # material subordinate to the conversation memory.
    <<~KNOW.strip
      BASE DE CONHECIMENTO (referência factual — NÃO é roteiro para recitar):
      Consulte para responder o que o cliente pergunta. Se algum item trouxer
      um roteiro de qualificação (ex.: "pergunte tipo de fio, química,
      objetivo"), trate como guia INTERNO — só pergunte o que ainda NÃO está
      na MEMÓRIA DA CONVERSA. Com os dados em mãos, avance para recomendação.
      #{bullets}
    KNOW
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
