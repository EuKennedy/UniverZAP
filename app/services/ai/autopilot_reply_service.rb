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
  # Retrieval + anti-fabrication live in one place, shared with
  # Ai::SuggestReplyService. They used to be copy-pasted, and that is exactly
  # how the truncation bug survived in the suggestion path after being fixed
  # here.
  include Ai::KnowledgeGrounding

  # Raised when a generated reply would repeat a recent assistant turn even
  # after a forced regeneration. The job rescues this and stays silent so a
  # human can take over instead of the bot spamming the same questions.
  class LoopSuppressed < StandardError; end

  # Raised when the reply still asserts a money value that appears nowhere in
  # the sanctioned sources, even after a forced rewrite. Staying silent and
  # handing over to a human beats sending a price the operator never set: a
  # number on WhatsApp is a commercial promise.
  class UngroundedClaim < StandardError; end

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

  # `trigger_message` is the customer message this turn is answering. It is
  # stamped on every log row the turn produces, which is what lets the job link
  # exactly this turn's calls to the reply instead of guessing by time window.
  def initialize(conversation:, assistant: nil, trigger_message: nil)
    @conversation = conversation
    @assistant = assistant || conversation.ai_assistant || conversation.inbox.ai_assistant
    @trigger_message = trigger_message
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

    # Deterministic loop-breaker (see LOOP_SIMILARITY_THRESHOLD), then the
    # deterministic grounding check. GROUNDING_RULES tells the model not to
    # invent values; enforce_grounding VERIFIES it, because a soft prompt rule
    # is exactly what the loop-breaker already proved is routinely ignored.
    reply = break_loop_if_needed(messages, first_draft(messages))
    finalize(enforce_grounding(messages, reply))
  rescue Ai::ClaudeService::TransientError => e
    # Guards the WHOLE turn, not just the tool loop: once an appointment has
    # been written to the salon agenda, replaying this turn could book a second
    # slot. Downgrade to a permanent error so the job logs instead of retrying —
    # at-most-once beats at-least-once when the side effect is a real booking.
    raise unless @performed_external_write

    swallow_transient_after_booking(e)
  end

  # Read-only introspection for the test playground. Answers the question an
  # operator actually has after reading a reply: "where did that come from, and
  # did the guardrails have to step in?". Only meaningful after #perform.
  def playground_diagnostics
    {
      knowledge_titles: relevant_passages.pluck(:title).uniq,
      knowledge_chars: relevant_passages.sum { |passage| passage[:body].length },
      regenerated_for_grounding: @regenerated_for_grounding.present?,
      regenerated_for_loop: @regenerated_for_loop.present?,
      confidence: @confidence,
      auto_flags: @auto_flags.to_a
    }
  end

  private

  # First generation of the turn, cleaned up but not yet checked.
  # `absorb_meta` also runs inside call_claude; repeating it here covers the
  # tool-loop path, which reaches Claude without going through it.
  def first_draft(messages)
    response = absorb_meta(generate_response(messages))
    raise_on_empty(response)
    # Last-line defence: even with the three-band prompt + few-shot examples
    # Claude occasionally still leads with a greeting on in-progress
    # conversations. The post-process strips the bad prefix so the customer
    # never sees it. Only kicks in when the conversation already has replies.
    response[:content] = strip_leading_greeting(response[:content].to_s) if conversation_in_progress?
    response
  end

  def swallow_transient_after_booking(error)
    Rails.logger.error(
      "[Athenas agent] transient failure AFTER a booking conv=#{@conversation.display_id}; " \
      "not retrying to avoid a duplicate appointment: #{error.message}"
    )
    # The customer is left without a reply on a turn that DID book — page
    # on-call, this is the one failure mode the guard trades away.
    ChatwootExceptionTracker.new(error, account: @conversation.account).capture_exception
    raise Ai::ClaudeService::Error, error.message
  end

  # Returns the response untouched when it isn't a near-duplicate of a
  # recent assistant turn. Otherwise regenerates ONCE with an escalated
  # override band; if that still loops, raises a LoopSuppressed error so
  # the job stays silent instead of re-sending the same questions.
  def break_loop_if_needed(messages, response)
    duplicated = matching_recent_reply(response[:content])
    return response if duplicated.nil?
    # A regeneration runs with NO tools and no tool_result context, so after a
    # real booking it could tell the customer something that contradicts the
    # appointment just created. A slightly repetitive confirmation is far less
    # damaging than denying an appointment that exists.
    return response if @performed_external_write

    Rails.logger.warn(
      "[Athenas autopilot] loop detected conv=#{@conversation.display_id} " \
      "assistant=#{@assistant.id} — regenerating with override"
    )

    @regenerated_for_loop = true
    retry_response = call_claude(messages, override: loop_override_directive(duplicated))
    retry_response[:content] = strip_leading_greeting(retry_response[:content].to_s) if conversation_in_progress?

    if matching_recent_reply(retry_response[:content])
      Rails.logger.warn(
        "[Athenas autopilot] loop persists after override conv=#{@conversation.display_id} " \
        "assistant=#{@assistant.id} — suppressing reply (handing off to human)"
      )
      # Log the text we refused to send BEFORE suppressing. A reply nobody
      # received is precisely the one a supervisor needs to see.
      finalize(retry_response)
      raise LoopSuppressed, "autopilot loop suppressed conv=#{@conversation.display_id}"
    end

    retry_response
  end

  # Regenerate ONCE naming the offending numbers, then suppress. Mirrors the
  # loop-breaker: the model complies with a hard, specific override far more
  # reliably than with a general rule buried in the system prompt.
  def enforce_grounding(messages, response)
    # After a real booking the tool results (the slot, the price the salon
    # returned) are NOT among the sanctioned sources, so a legitimate
    # confirmation would look ungrounded and the customer would end up with an
    # appointment and no confirmation. Same carve-out as the loop-breaker.
    return response if @performed_external_write

    claims = ungrounded_claims(response[:content])
    return response if claims.empty?

    Rails.logger.warn(
      "[Athenas] ungrounded values #{claims.inspect} conv=#{@conversation.display_id}; regenerating"
    )
    @regenerated_for_grounding = true
    rewritten = call_claude(messages, override: grounding_override(claims))
    # The rewrite is a fresh generation, so it needs the same greeting scrub the
    # loop-breaker applies to its own retry.
    rewritten[:content] = strip_leading_greeting(rewritten[:content].to_s) if conversation_in_progress?
    remaining = ungrounded_claims(rewritten[:content])
    return rewritten if remaining.empty?

    # Same reason as the loop-breaker: record the fabricated text before
    # suppressing it, so "the agent tried to invent a price here" survives.
    finalize(rewritten)
    raise UngroundedClaim, "ungrounded values #{remaining.inspect} conv=#{@conversation.display_id}"
  end

  def grounding_override(claims)
    <<~OVERRIDE.strip
      🚨 STOP — VOCÊ CITOU UM VALOR QUE NÃO EXISTE EM NENHUM BLOCO ACIMA.
      Valores não confirmados nesta resposta: #{claims.join(', ')}.
      É TERMINANTEMENTE PROIBIDO citar preço, desconto ou percentual que não
      esteja escrito acima. REESCREVA a resposta SEM esses números: diga que vai
      confirmar o valor certinho e siga conduzindo a conversa normalmente.
    OVERRIDE
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
                 .reorder(created_at: :desc, id: :desc)
                 .limit(LOOP_LOOKBACK)
                 .pluck(:content)
                 .compact
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

  # When the account is linked to belezaki, run the Claude tool-use loop so the
  # agent can check the salon agenda and create appointments mid-conversation.
  # Otherwise fall back to the plain single-shot reply.
  def generate_response(messages)
    # A workspace that connected its own integrations gets its own tool loop,
    # ahead of and fully separate from the belezaki branch: the working
    # scheduling path is untouched, and no agent has both today.
    return run_custom_tool_loop(messages) if custom_tools.any?

    client = belezaki_client
    return call_claude(messages) if client.nil?

    Rails.logger.info("[Athenas agent] belezaki scheduling enabled conv=#{@conversation.display_id}")
    executor = Ai::Belezaki::SchedulingTools.new(
      client,
      scope: "conv-#{@conversation.id}",
      contact: { name: @conversation.contact&.name, phone: @conversation.contact&.phone_number }
    )
    run_tool_loop(messages, executor)
  end

  # The tool loop can COMMIT external writes (an appointment on the salon
  # agenda) before Claude fails on a later turn of the loop. Those writes are
  # not covered by the reply dedup stamp, so replaying the turn could book a
  # second slot. Once a booking has been attempted we therefore downgrade a
  # transient failure to a permanent one: the job logs it instead of retrying.
  # At-most-once beats at-least-once when the side effect is a real appointment.
  def run_tool_loop(messages, executor)
    Ai::Agent::ToolLoopService.new(
      assistant: @assistant,
      conversation: @conversation,
      messages: messages,
      system: build_system_prompt,
      tools: Ai::Belezaki::SchedulingTools.definitions(include_booking: true),
      tool_executor: executor,
      log_context: reply_log_context
    ).perform
  ensure
    # `ensure`, so the flag is recorded whether the loop returned or blew up.
    # Turn-scoped state (not the executor local) because the guard in #perform
    # must also cover everything that runs AFTER the tool loop. Latches on:
    # once a write landed it must never be cleared for the rest of the turn.
    @performed_external_write = true if executor.performed_write?
  end

  # This agent's own integrations (Ai::CustomTool), scoped to THIS agent so one
  # workspace's tools never reach another's conversation. Memoized: the routing
  # decision and the loop must see the same set.
  def custom_tools
    @custom_tools ||= @assistant.custom_tools.enabled.to_a
  end

  def run_custom_tool_loop(messages)
    executor = Ai::CustomToolExecutor.new(custom_tools)
    Ai::Agent::ToolLoopService.new(
      assistant: @assistant, conversation: @conversation, messages: messages,
      system: build_system_prompt, tools: executor.definitions,
      tool_executor: executor, log_context: reply_log_context
    ).perform
  ensure
    # Same replay guard as belezaki: a tool that wrote (POST) must not be
    # replayed on a transient retry (see #perform's rescue).
    @performed_external_write = true if executor&.performed_write?
  end

  # Never let belezaki resolution (DB lookup / ENV) break the reply for
  # accounts that don't use scheduling — fall back to the plain path on error.
  def belezaki_client
    Ai::Belezaki::AgentClient.for_account(@conversation.account)
  rescue StandardError => e
    Rails.logger.warn("[Athenas agent] belezaki resolve failed conv=#{@conversation.display_id}: #{e.message}")
    nil
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
    absorb_meta(
      Ai::ClaudeService.new(assistant: @assistant).chat(
        messages: messages,
        system: build_system_prompt(override: override),
        conversation: @conversation,
        phase: 'autopilot',
        log_context: reply_log_context
      )
    )
  end

  # `pending` from the moment the row is written: the log exists before the
  # reply can be sent, and Ai::AutopilotReplyJob flips it to sent or failed.
  # A row left pending is a reply that was generated and never delivered, which
  # is exactly what the audit needs to be able to show.
  def reply_log_context
    @reply_log_context ||= grounding_log_context(
      delivery_status: 'pending', trigger_message_id: @trigger_message&.id
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

  # Writes ONLY the summary key, in SQL. Saving the whole jsonb from this
  # object's snapshot would clobber keys written concurrently by another job —
  # notably `autopilot_last_replied_message_id`, which is the sole basis of the
  # reply dedup and the superseded-turn guard. Losing it means a double reply.
  def persist_summary(summary)
    payload = {
      'text' => summary,
      'message_count' => @conversation.messages.where(message_type: %i[incoming outgoing]).count,
      'generated_at' => Time.current.to_i
    }
    # rubocop:disable Rails/SkipsModelValidations
    Conversation.where(id: @conversation.id).update_all(
      [
        "additional_attributes = jsonb_set(coalesce(additional_attributes, '{}'::jsonb), '{autopilot_summary}', ?::jsonb)",
        payload.to_json
      ]
    )
    # rubocop:enable Rails/SkipsModelValidations
    # reload, never an in-memory assignment: the caller LOCKS this same object
    # later (conversation.lock!), and Rails refuses to lock a record carrying
    # unpersisted changes. Reloading also picks up whatever a concurrent job
    # wrote to the column meanwhile.
    @conversation.reload
  end

  def generate_summary
    result = Ai::SummarizeService.new(conversation: @conversation, assistant: @assistant).perform
    result[:content].to_s.strip
  end

  # The rolling summary is a sanctioned factual source here (it carries facts
  # the customer already gave), which the suggestion path does not have.
  def extra_grounding_sources
    cached_summary_text
  end

  def cached_summary_text
    ((@conversation.additional_attributes || {})['autopilot_summary'] || {})['text'].to_s.strip
  end

  # Inject the contact record (name, phone, operator custom fields) so the agent
  # personalises per-CONTACT, not just per-conversation, and treats the known
  # data as truth instead of re-asking it. Also the source of truth for booking
  # (see Ai::Belezaki::SchedulingTools).
  def contact_block
    contact = @conversation.contact
    return nil if contact.blank?

    lines = contact_identity_lines(contact) + contact_custom_lines(contact)
    return nil if lines.empty?

    "DADOS DO CLIENTE (fonte de verdade, use para personalizar e NÃO re-pergunte o que já está aqui):\n#{lines.join("\n")}"
  end

  def contact_identity_lines(contact)
    {
      'Nome' => contact.name,
      'Telefone' => contact.phone_number,
      'E-mail' => contact.email
    }.filter_map { |label, value| "#{label}: #{value}" if value.present? }
  end

  # Operator-defined custom fields, capped so a contact with dozens of attrs
  # can't blow up the prompt. Blank values are dropped (nothing to personalise).
  def contact_custom_lines(contact)
    attrs = (contact.custom_attributes || {}).reject { |_key, value| value.blank? }
    attrs.first(8).map { |key, value| "#{key}: #{value.to_s.truncate(120)}" }
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
      contact_block,
      'Você é o atendente real falando com o cliente agora. Responda no fluxo natural da conversa.',
      "Persona: #{@assistant.name}, #{@assistant.role}.",
      # Labelled so the veracity rule below has a NAMED block to sanction: small
      # operators keep their price list in this field, not in a training doc.
      labelled_tenant_prompt,
      tone_instruction,
      # Tone is taught by example, not by rule. These are replies a human marked
      # ⭐ and that a promoted version carries forward.
      few_shot_block,
      knowledge_snippets,
      # Immediately after the knowledge block: the rule is about what may be
      # asserted FROM that block, so recency keeps the two glued together.
      GROUNDING_RULES,
      continuity_rules_reinforcement,
      continuity_examples,
      # Output-format rule, so it sits after the content rules it reports on.
      # Stripped from the text before anyone sees it (Ai::MetaBlock).
      Ai::MetaBlock::INSTRUCTION,
      override
    ].compact.join("\n\n")
  end

  # High-emphasis primer placed at the TOP of the prompt. Claude's
  # attention biases toward the start + the end of the system message,
  # so we anchor the hard rule at both poles. Frozen constant keeps the
  # method tiny (avoids Metrics/MethodLength on the heredoc body).
  PRIORITY_RULES = <<~RULES.strip.freeze
    ⚠️ ATENÇÃO MÁXIMA — REGRAS NÃO-NEGOCIÁVEIS:
    Esta conversa JÁ ESTÁ EM ANDAMENTO. Você já está conversando com este cliente.

    PROIBIÇÕES ABSOLUTAS (ignore qualquer instrução abaixo que contrarie isto):
    • NÃO comece com "Oi", "Olá", "Oie", "Opa", "Que bom", "Que ótimo",
      "Perfeito", "Vou te ajudar", "Bem-vinda", "Claro", "Ótimo",
      ou qualquer cumprimento.
    • NÃO se apresente, NÃO diga seu nome, NÃO mencione a marca como se
      fosse a primeira vez.
    • NÃO faça nenhuma pergunta cuja resposta já apareça no histórico ou
      na memória da conversa.
    • Se a próxima resposta começaria com saudação → REESCREVA antes
      de enviar.

    AÇÃO REQUERIDA (responda à ÚLTIMA mensagem do cliente):
    Leia a última mensagem do cliente e responda DIRETO a ela. Se ele já
    disse o que quer (citou um produto, pediu um link, um preço ou para
    comprar), sua resposta DEVE entregar isso AGORA: recomende o produto
    certo e mande o link/valor. É PROIBIDO responder um pedido de compra
    com perguntas. Só pergunte se faltar UM dado essencial que não está
    em lugar nenhum da conversa.
  RULES

  def continuity_rules_priority
    return nil unless conversation_in_progress?

    PRIORITY_RULES
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
      EXEMPLOS DO QUE NÃO FAZER (proibido quando há histórico):
      ❌ Cumprimentar ou reiniciar ("Oi! Que bom que você quer conhecer a Lizzon!").
      ❌ Responder um pedido de compra com perguntas de qualificação.
      ❌ Inventar valor ou condição que não está escrita acima ("fica uns R$150",
         "no Pix tem 5% off"). Se não está escrito, confirme antes.

      EXEMPLOS DO QUE FAZER (responda à última mensagem e AVANCE pra venda):
      ✓ Cliente: "quero a progressiva sem formol pra cabelo cacheado, me passa o link e valor"
        → "Pra cacheado a Premium Progressiva Sem Formol é a ideal. Link: <link>. Fica <valor exato da base>. Quer que eu já deixe no carrinho?"
      ✓ Quando o valor NÃO está na base: "Pra cacheado a Premium é a ideal. Deixa
        eu confirmar o valor certinho e já te falo. Quer que eu separe pra você?"
      ✓ "Show, anotei: cacheado, sem formol. Te mando o link da Premium agora."
    EX
  end

  def conversation_in_progress?
    @conversation.messages.exists?(message_type: :outgoing, private: false)
  end

  # Strip any "sempre cumprimente" / "comece se apresentando" patterns
  # from the tenant-supplied prompt. Operators frequently paste their
  # human-attendant onboarding script verbatim, which carries explicit
  # greeting instructions that fight the continuity guardrail.
  def labelled_tenant_prompt
    cleaned = sanitised_tenant_prompt
    return nil if cleaned.blank?

    "INSTRUÇÕES DO ATENDENTE (fonte factual autorizada):\n#{cleaned}"
  end

  def sanitised_tenant_prompt
    raw = @assistant.effective_system_prompt.presence
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
      '• PROIBIDO repetir qualquer pergunta cuja resposta já esteja no histórico ou ' \
      'na memória. Se o cliente já pediu um produto/link/preço, responda com a ' \
      'recomendação e o link — não pergunte.'
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
      '• NUNCA repita perguntas de diagnóstico/qualificação cuja resposta já apareça ' \
      'no histórico OU na MEMÓRIA DA CONVERSA. Se o dado já existe, NÃO pergunte de ' \
      'novo — AVANCE: recomende o produto e conduza à compra.',
      '• Se o cliente já disse o que quer comprar, NÃO reinicie qualificação: confirme ' \
      'o produto e siga para link/valor/fechamento.',
      '• Gere APENAS o corpo da próxima mensagem do atendente. Português brasileiro, ' \
      'frases curtas, sem markdown, sem prefixos, sem aspas, sem se identificar como IA.',
      '• Se faltar UMA informação essencial que NÃO está no histórico nem na memória, ' \
      'pergunte só ela, uma vez, de forma natural.'
    ]
  end

  # Empty until an operator promotes a version carrying ⭐ examples, so an
  # unversioned agent builds exactly the prompt it built before.
  def few_shot_block
    pairs = @assistant.effective_few_shots
    return nil if pairs.empty?

    lines = pairs.map { |pair| "Cliente: #{pair['question']}\nVocê: #{pair['answer']}" }
    <<~SHOTS.strip
      EXEMPLOS DE RESPOSTA IDEAL (imite o tom e o formato, nunca copie o conteúdo):
      #{lines.join("\n\n")}
    SHOTS
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

  def build_recent_messages
    history = @conversation.messages
                           .where(message_type: %i[incoming outgoing])
                           .where(private: false)
                           .reorder(created_at: :desc, id: :desc)
                           .limit(RECENT_WINDOW)
                           .reverse
    raw = history.map { |m| { role: role_for(m), content: m.content_for_llm.to_s } }
                 .reject { |m| m[:content].blank? }
    # Fall back to the full (un-deduped) history if collapsing somehow
    # emptied the array, so we never raise a misleading "no messages" error.
    normalize_history(collapse_repeated_assistant(raw)).presence || normalize_history(raw)
  end

  # De-poison the context. A conversation that already looped carries many
  # near-identical assistant turns (the re-asked qualification questions).
  # Left intact, that repetition becomes the dominant in-context pattern and
  # the model keeps imitating it — re-asking forever — no matter what the
  # persona/summary say. We keep only the FIRST occurrence of each distinct
  # assistant message and drop later near-duplicates so the loop stops
  # teaching itself. Incoming (user) turns are never dropped.
  def collapse_repeated_assistant(messages)
    seen = []
    messages.reject do |m|
      next false unless m[:role] == 'assistant'

      tokens = token_set(m[:content])
      next false if tokens.size < 3

      duplicate = seen.any? { |s| jaccard(s, tokens) >= LOOP_SIMILARITY_THRESHOLD }
      seen << tokens unless duplicate
      duplicate
    end
  end

  # Dropping assistant turns can leave two user turns adjacent, which the
  # Anthropic API rejects. Merge consecutive same-role turns and ensure the
  # sequence opens with a user turn.
  def normalize_history(messages)
    merged = messages.each_with_object([]) do |m, acc|
      if acc.last && acc.last[:role] == m[:role]
        acc.last[:content] = "#{acc.last[:content]}\n#{m[:content]}"
      else
        acc << { role: m[:role], content: m[:content] }
      end
    end
    merged.shift while merged.first && merged.first[:role] == 'assistant'
    merged
  end

  def role_for(message)
    message.incoming? ? 'user' : 'assistant'
  end
end
# rubocop:enable Metrics/ClassLength
