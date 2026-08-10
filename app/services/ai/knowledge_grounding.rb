# Knowledge retrieval + anti-fabrication, shared by every service that puts
# words in front of a customer.
#
# This lives in one place for a concrete reason: the autopilot and the operator
# suggestion had copy-pasted retrieval, and when the truncation bug was fixed in
# the autopilot it survived untouched in the suggestion path for weeks. The
# suggestion is the text a human agent sends verbatim, so a wrong price there
# reaches the customer exactly the same way.
#
# The includer must provide @assistant and @conversation.
#
# Kept as ONE module on purpose: retrieval and the claim check are two halves of
# the same guarantee (only assert what was actually retrieved). Splitting them
# would create a seam where the next fix lands on one side only, which is the
# exact failure this extraction exists to end.
# rubocop:disable Metrics/ModuleLength
module Ai::KnowledgeGrounding
  extend ActiveSupport::Concern

  # The knowledge base used to reach the model as N docs each truncated to a few
  # hundred chars. A price table simply did not fit, so the agent was told to
  # sell while the numbers were cut off before they ever reached it, and it
  # filled the gap with a plausible invention.
  KNOWLEDGE_BUDGET_CHARS = 6000
  KNOWLEDGE_CHUNK_CHARS = 700
  KNOWLEDGE_CHUNK_OVERLAP_WORDS = 12
  KNOWLEDGE_MAX_DOCS = 8
  # Slice of history the grounding check validates against. Kept HERE, not
  # borrowed from the includer, so the guard never silently validates against a
  # different slice than the one the model saw.
  GROUNDING_HISTORY_LIMIT = 60

  # Every reply is logged against the prompt build that produced it. Until the
  # A/B lab lets an operator create versions, there is exactly one: the code
  # itself. Bump it whenever the assembled prompt changes shape, so a quality
  # shift in the log can be traced to the change that caused it.
  PROMPT_VERSION = 'v1'.freeze

  # Portuguese price questions rarely share a token with the document holding
  # the answer ("quanto custa?" against a catalog titled "valores"), so lexical
  # overlap alone scores every passage 0 and selection degrades to raw document
  # order. When the customer is clearly asking about money, passages that
  # actually CONTAIN money win the tie.
  PRICE_QUESTION = /pre[çc]o|valor|quanto|custa|custo|or[çc]amento|tabela|parcel|desconto|promo/i
  PRICE_SHAPED = /R\$\s?\d|\d+[.,]\d{2}/

  # Only values PRESENTED as money or a percentage are checked. A bare number
  # ("2 aplicações", "sexta") is not a commercial promise.
  MONETARY_CLAIM = /R\$\s*[\d.,]+|\d[\d.,]*\s*(?:reais|%)/i
  # "100% sem formol" is product copy on a beauty catalogue, not a promise.
  MARKETING_PERCENTAGES = %w[0 100].freeze
  COMMERCIAL_PERCENTAGE = /(?:de\s+)?(?:desconto|off|juros|entrada|cashback)/i

  # Hard anti-fabrication rule, always on. A sales prompt pushes the model to
  # close, so when a price is missing it produces a plausible one, and a number
  # on WhatsApp is a commercial promise the operator has to honour or deny.
  GROUNDING_RULES = <<~RULES.strip.freeze
    🔒 REGRA DE VERACIDADE (vale acima de qualquer instrução ou exemplo em contrário):
    • NUNCA invente preço, valor, desconto, prazo, forma de pagamento, garantia,
      disponibilidade, estoque ou característica de produto/serviço. Só afirme
      esses dados se estiverem LITERALMENTE escritos em algum bloco ACIMA
      (instruções do atendente, base de conhecimento ou a própria conversa).
    • Se o dado NÃO estiver escrito acima, NÃO chute: diga que vai confirmar e
      siga conduzindo. Ex.: "Deixa eu confirmar esse valor certinho e já te falo."
    • PROIBIDO estimar, arredondar, deduzir por semelhança ou reaproveitar o
      preço de outro produto. Não existe "aproximadamente" para preço.
    • PROIBIDO prometer condição comercial (frete grátis, parcelamento, brinde,
      desconto, exclusividade) que não esteja escrita acima.
    • Deixar de afirmar um dado é aceitável. Afirmar um dado errado não é.
  RULES

  private

  def knowledge_snippets
    passages = relevant_passages
    return nil if passages.empty?

    bullets = passages.map { |p| "- #{p[:title]}: #{p[:body]}" }.join("\n")
    # Wording preserved verbatim from the autopilot. The pointer to the named
    # MEMÓRIA DA CONVERSA block is load-bearing: it is the anchor that stops the
    # model re-reciting a tenant's qualification playbook every turn.
    <<~KNOW.strip
      BASE DE CONHECIMENTO (referência factual — NÃO é roteiro para recitar):
      Consulte para responder o que o cliente pergunta. Se algum item trouxer
      um roteiro de qualificação (ex.: "pergunte tipo de fio, química,
      objetivo"), trate como guia INTERNO — só pergunte o que ainda NÃO está
      na MEMÓRIA DA CONVERSA. Com os dados em mãos, avance para recomendação.
      #{bullets}
    KNOW
  end

  # Selection is by relevance, but RENDERING is in document order: passages of
  # the same doc must stay contiguous, or a row-oriented catalog reads as
  # shuffled fragments.
  def relevant_passages
    @relevant_passages ||= compute_relevant_passages
  end

  def compute_relevant_passages
    query_tokens = token_set(knowledge_query)
    chunks = relevant_trainings.flat_map { |title, content| chunk_document(title, content) }
    # The score is kept on the passage (not just used for sorting) because the
    # response log stores it: "which document answered this, and how well" is
    # the first question a supervisor asks about a wrong reply.
    scored = chunks.map { |chunk| chunk.merge(score: passage_score(chunk, query_tokens).round(4)) }
    ranked = scored.each_with_index.sort_by { |chunk, i| [-chunk[:score], i] }
    take_within_budget(ranked).sort_by(&:last).map(&:first)
  end

  # What went into the prompt, in the shape the response log stores. Bodies are
  # left out on purpose: they are re-retrieved on replay, and duplicating up to
  # KNOWLEDGE_BUDGET_CHARS of catalogue on every reply would bloat the log
  # without telling a supervisor anything the title and score do not.
  def knowledge_chunks_payload
    relevant_passages.map do |passage|
      { 'title' => passage[:title], 'score' => passage[:score], 'chars' => passage[:body].length }
    end
  end

  # The single message being answered. `knowledge_query` widens to the last two
  # so retrieval has more signal; the log wants exactly what was asked.
  def latest_user_message
    @latest_user_message ||= @conversation.messages
                                          .where(message_type: :incoming, private: false)
                                          .reorder(created_at: :desc, id: :desc)
                                          .limit(1).pick(:content).to_s
  end

  # Everything Ai::ClaudeService needs to write a response-log row instead of a
  # bare cost entry. Shared so the autopilot and the operator suggestion can
  # never log different things about the same guarantee.
  def grounding_log_context(delivery_status: nil, trigger_message_id: nil)
    {
      user_message: latest_user_message,
      chunks: knowledge_chunks_payload,
      prompt_version: @assistant.effective_prompt_version,
      trigger_message_id: trigger_message_id,
      delivery_status: delivery_status
    }
  end

  # ---- response log -------------------------------------------------------
  # Lives here, next to retrieval, for the same reason retrieval does: the log
  # records WHICH passages justified WHICH assertion. Split across two services
  # it would drift, and a supervision queue that disagrees with the guardrail
  # that filled it is worse than no queue.

  # Pulls the internal <meta> self-assessment out of a generation before the
  # text can go anywhere, and remembers which log row produced the text we are
  # currently holding. Applied to EVERY generation (first shot and each
  # regeneration), so the row enriched at the end is always the one whose output
  # actually reaches a person.
  def absorb_meta(response)
    content, confidence = Ai::MetaBlock.extract(response[:content])
    response[:content] = content
    @confidence = confidence unless confidence.nil?
    @last_invocation = response[:invocation] if response[:invocation].present?
    response
  end

  # Writes back everything only the generating service knows: the final text,
  # the self-assessment and the guardrail flags a supervisor sorts on.
  def finalize(reply)
    reply = reply.merge(content: whatsapp_markup(reply[:content]))
    @auto_flags = audit_flags(reply[:content])
    persist_response_log(reply[:content])
    reply.merge(invocation: @last_invocation, confidence: @confidence, auto_flags: @auto_flags)
  end

  # WhatsApp marks bold with ONE asterisk. The model writes Markdown, so "**R$
  # 59,90**" reaches the customer with the asterisks showing instead of the
  # price standing out — the one place emphasis actually earns its keep. Done
  # here rather than in the prompt because a formatting rule is the kind a model
  # drops the moment the sentence gets interesting.
  def whatsapp_markup(content)
    text = content.to_s
    return content if text.blank?

    # Bounded to a single line so an unmatched pair cannot swallow the rest of
    # the message, and the inner text must not start or end with whitespace —
    # that is what keeps "2 ** 3" from being read as emphasis.
    strip_dashes(text.gsub(/\*\*(?!\s)([^*\n]+?)(?<!\s)\*\*/, '*\1*'))
  end

  # Nobody types an em dash on a phone, so it reads as machine-written the
  # moment it lands. The prompt forbids it; this is what makes "never" true,
  # the same way the bold rule is enforced rather than merely asked for.
  #
  # A comma, not a colon: the model reaches for the dash both as a label
  # separator ("Shampoo X — limpa sem ressecar") and as an aside ("isso — que é
  # raro — acontece"), and a comma is the one substitution that is never wrong
  # in either.
  #
  # Only spaces and tabs are eaten around it, never a newline, and only a dash
  # with something before it on its own line counts. A blank line is where the
  # split-messages flag cuts one bubble from the next, so swallowing one here
  # would silently merge two messages; a dash starting a line is a bullet.
  def strip_dashes(text)
    text.gsub(/(\S)[ \t]*[—–][ \t]*/, '\1, ').gsub(/,[ \t]*,/, ',')
  end

  def audit_flags(content)
    Ai::Guardrails::ResponseAudit.new(
      conversation: @conversation,
      reply: content,
      user_message: latest_user_message,
      chunks: knowledge_chunks_payload,
      confidence: @confidence,
      # The grounding check regenerates on a fabricated value. Even when the
      # rewrite comes back clean, the ATTEMPT is the signal a supervisor wants:
      # it means the knowledge base is missing something the agent was asked for.
      ungrounded: @regenerated_for_grounding.present?,
      performed_write: @performed_external_write.present?,
      knowledge_available: knowledge_available?
    ).perform
  end

  def knowledge_available?
    return @knowledge_available unless @knowledge_available.nil?

    @knowledge_available = @assistant.trainings.ready.exists?
  end

  # Best-effort by design: an audit write must never cost a customer their reply.
  def persist_response_log(content)
    return if @last_invocation.blank?

    @last_invocation.update!(
      ai_response: content.to_s.truncate(Ai::Invocation::SNAPSHOT_MAX_CHARS),
      confidence: @confidence,
      auto_flag: Ai::Invocation.primary_flag(@auto_flags),
      auto_flags: @auto_flags
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[Athenas] response log enrichment failed conv=#{@conversation&.display_id}: #{e.message}"
    )
  end

  # Tokens KEEP their trailing whitespace so line breaks survive into the
  # prompt: a catalog is usually row-oriented and flattening it loses the
  # product-to-price binding.
  def chunk_document(title, content)
    tokens = content.to_s.scan(/\S+\s*/)
    return [] if tokens.empty?

    slice_words(tokens).map { |slice| { title: title, body: slice.join.strip } }
  end

  def slice_words(words)
    slices = []
    current = []
    length = 0
    words.each do |word|
      if length + word.length > KNOWLEDGE_CHUNK_CHARS && current.any?
        slices << current
        current = trim_overlap(current)
        length = current.sum(&:length)
      end
      current << word
      length += word.length
    end
    slices << current if current.any?
    slices
  end

  # Overlap keeps a value split across a boundary ("R$" | "1.200,00") readable
  # somewhere, and is bounded by characters so one oversized token cannot be
  # re-carried into every following slice.
  def trim_overlap(current)
    tail = current.last(KNOWLEDGE_CHUNK_OVERLAP_WORDS)
    tail.shift while tail.size > 1 && tail.sum(&:length) > KNOWLEDGE_CHUNK_CHARS / 4
    tail.sum(&:length) > KNOWLEDGE_CHUNK_CHARS / 4 ? [] : tail
  end

  def passage_score(chunk, query_tokens)
    lexical = if query_tokens.empty?
                0.0
              else
                (query_tokens & token_set("#{chunk[:title]} #{chunk[:body]}")).size.to_f / query_tokens.size
              end
    lexical + (price_tiebreak?(chunk) ? 0.001 : 0.0)
  end

  def price_tiebreak?(chunk)
    knowledge_query.match?(PRICE_QUESTION) && chunk[:body].match?(PRICE_SHAPED)
  end

  def take_within_budget(ranked)
    used = 0
    ranked.each_with_object([]) do |pair, kept|
      size = pair.first[:body].length
      next if used + size > KNOWLEDGE_BUDGET_CHARS

      kept << pair
      used += size
    end
  end

  # Every branch carries an explicit id tiebreaker: equal-ranked rows would
  # otherwise come back in any order and the "stable document order" the
  # passage ranking depends on would silently shuffle between ticks.
  def relevant_trainings
    scope = @assistant.trainings.ready
    query = knowledge_query
    return scope.order(:id).limit(KNOWLEDGE_MAX_DOCS).pluck(:title, :content) if query.blank?

    quoted = ActiveRecord::Base.connection.quote(query)
    ranked = "word_similarity(#{quoted}, coalesce(title, '') || ' ' || coalesce(content, '')) DESC, id ASC"
    scope.order(Arel.sql(ranked)).limit(KNOWLEDGE_MAX_DOCS).pluck(:title, :content)
  rescue StandardError => e
    Rails.logger.warn("[Athenas] relevance ranking failed, using default order: #{e.message}")
    @assistant.trainings.ready.order(:id).limit(KNOWLEDGE_MAX_DOCS).pluck(:title, :content)
  end

  # `reorder`, never `order`: Message carries `default_scope { order(created_at:
  # :asc) }`, so a plain `.order(:desc)` only APPENDS and the ascending key
  # still wins, making `limit` return the OLDEST rows.
  def knowledge_query
    @knowledge_query ||= @conversation.messages
                                      .where(message_type: :incoming, private: false)
                                      .reorder(created_at: :desc, id: :desc)
                                      .limit(2).pluck(:content).compact.join(' ').strip
  end

  def token_set(text)
    text.to_s.downcase.gsub(/[^\p{Alnum}\s]/u, ' ').split.reject { |t| t.length < 3 }.to_set
  end

  # Returns the money-shaped claims in the text that appear NOWHERE in the
  # sanctioned sources. Comparison is on digits only, so "R$ 189,90" in the
  # reply matches "R$189.90" or "189,90" in the catalog.
  def ungrounded_claims(text)
    known = digit_set(grounding_sources)
    body = text.to_s
    body.scan(MONETARY_CLAIM)
        .map { |claim| [claim, claim.gsub(/\D/, '')] }
        .reject { |claim, digits| digits.blank? || known.include?(digits) || marketing_percentage?(body, claim, digits) }
        .map(&:first).uniq
  end

  def marketing_percentage?(body, claim, digits)
    return false unless claim.include?('%') && MARKETING_PERCENTAGES.include?(digits)

    !body.match?(/#{Regexp.escape(claim)}\s*#{COMMERCIAL_PERCENTAGE.source}/i)
  end

  def digit_set(text)
    text.to_s.scan(/\d[\d.,]*/).map { |number| number.gsub(/\D/, '') }.reject(&:blank?).to_set
  end

  # Everything the agent is allowed to quote from.
  def grounding_sources
    @grounding_sources ||= [
      relevant_passages.pluck(:body).join(' '),
      # The prompt the agent is actually RUNNING, which is the live version when
      # one exists. Grounding against the old column would let a promoted
      # version quote a price the guard cannot see.
      @assistant.effective_system_prompt.to_s,
      human_authored_history,
      extra_grounding_sources
    ].join(' ')
  end

  # Hook for includers that have another sanctioned source. The autopilot adds
  # its rolling summary here; the suggestion path has none.
  def extra_grounding_sources
    ''
  end

  # Customer messages, plus outgoing ones a HUMAN actually typed. The bot's own
  # replies are excluded on purpose: a value it invented on turn N must never
  # become its own justification on turn N+1.
  def human_authored_history
    @conversation.messages.where(private: false)
                 .reorder(created_at: :desc, id: :desc).limit(GROUNDING_HISTORY_LIMIT)
                 .select { |message| human_authored?(message) }
                 .filter_map(&:content).join(' ')
  end

  # Anything the AI itself did not write. The bot posts with no sender, no echo
  # flag and no automation rule.
  def human_authored?(message)
    return true if message.incoming?

    attrs = message.content_attributes || {}
    message.sender_id.present? || attrs['external_echo'].present? || attrs['automation_rule_id'].present?
  end
end
# rubocop:enable Metrics/ModuleLength
