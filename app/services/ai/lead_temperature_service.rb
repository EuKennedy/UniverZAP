# Scores a conversation that ended without a sale, 0 to 100.
#
# Deliberately hybrid. Sixty points come from signals that are cheap, stable and
# auditable: someone who asked a price and got a checkout link they never paid
# is interested, and that is true whether or not a model agrees. Forty come from
# one cheap model call, which is what reads intent and objection out of the
# actual words.
#
# A score built only from the model would cost a call per conversation, drift
# between runs, and be impossible to explain to the operator whose follow-up
# budget it spends.
class Ai::LeadTemperatureService
  # Deterministic signals, 60 points total.
  ASKED_PRICE = 20
  ASKED_SCHEDULE = 15
  ABANDONED_CHECKOUT = 15
  RETURNING_CUSTOMER = 10
  DECAY_PER_DAY = 2

  # The model reads intent, urgency and objection: 40 points, and the cheapest
  # model that can do it.
  READER_MODEL = 'claude-haiku-4-5-20251001'.freeze
  READER_MAX_TOKENS = 300

  PRICE_ASK = /pre[çc]o|valor|quanto\s+custa|quanto\s+(?:fica|sai|[ée])|or[çc]amento|tabela/i
  SCHEDULE_ASK = /hor[áa]rio|agenda|vaga|marcar|dispon[íi]vel|amanh[ãa]|semana|encaixe/i
  CHECKOUT_SENT = %r{https?://\S*(?:pay|checkout|carrinho|cart)}i
  PAID = /paguei|pago|comprei|finalizei\s+a\s+compra|conclu[íi]\s+o\s+pagamento/i

  def initialize(conversation:, assistant: nil)
    @conversation = conversation
    @assistant = assistant || conversation.ai_assistant || conversation.inbox.ai_assistant
  end

  # Returns the persisted opportunity, or nil when the conversation is not worth
  # tracking (it converted, or nobody said anything).
  def perform
    # No contact means nobody to follow up with, so there is no opportunity to
    # record even when the conversation looks interested.
    return nil if @assistant.blank? || @conversation.contact_id.blank? || customer_text.blank?

    reading = model_reading
    upsert(score(reading), reading)
  end

  private

  def score(reading)
    total = deterministic_points + reader_points(reading) - decay_points
    total.clamp(0, 100)
  end

  def deterministic_points
    points = 0
    points += ASKED_PRICE if customer_text.match?(PRICE_ASK)
    points += ASKED_SCHEDULE if customer_text.match?(SCHEDULE_ASK)
    points += ABANDONED_CHECKOUT if abandoned_checkout?
    points += RETURNING_CUSTOMER if returning_customer?
    points
  end

  # A link went out and nothing in the conversation says it was paid. Being
  # wrong here costs one follow-up message; missing it costs the sale.
  def abandoned_checkout?
    agent_text.match?(CHECKOUT_SENT) && !customer_text.match?(PAID)
  end

  def returning_customer?
    @conversation.contact.present? &&
      @conversation.contact.conversations.where.not(id: @conversation.id).exists?
  end

  # A hot lead that waits a week is not a hot lead. Decay is what stops the
  # radar filling up with three-month-old enthusiasm.
  def decay_points
    days = ((Time.current - last_activity_at) / 1.day).floor
    [days, 0].max * DECAY_PER_DAY
  end

  def last_activity_at
    @last_activity_at ||= @conversation.messages.maximum(:created_at) || @conversation.created_at
  end

  def reader_points(reading)
    return 0 if reading.blank?

    intent = reading['intencao_compra'].to_i.clamp(0, 15)
    urgency = reading['urgencia'].to_i.clamp(0, 10)
    objection = reading['objecao_forte'].to_i.clamp(-10, 0)
    # 15 + 10 leaves 15 for the plain fact that a human bothered to write: a
    # conversation that happened at all is worth more than one that did not.
    intent + urgency + objection + 15
  end

  def model_reading
    response = Ai::ClaudeService.new(assistant: @assistant).chat(
      messages: [{ role: 'user', content: reader_prompt }],
      system: READER_SYSTEM, model: READER_MODEL, max_tokens: READER_MAX_TOKENS,
      conversation: @conversation, phase: 'classifier'
    )
    parse_reading(response[:content])
  rescue StandardError => e
    # The deterministic 60 still stand. A scoring miss must never cost the
    # opportunity record itself.
    Rails.logger.warn("[Athenas radar] reading failed conv=#{@conversation.id}: #{e.message}")
    nil
  end

  READER_SYSTEM = <<~SYSTEM.strip.freeze
    Você analisa uma conversa de atendimento que terminou SEM venda e devolve
    APENAS um JSON, sem texto antes ou depois, exatamente neste formato:
    {"intencao_compra":0,"urgencia":0,"objecao_forte":0,"interesse":"",
    "valor_potencial":0,"motivo_bloqueio":"","acao_sugerida":""}

    intencao_compra: 0 a 15. urgencia: 0 a 10. objecao_forte: -10 a 0.
    interesse: o produto ou serviço que a pessoa queria, em poucas palavras.
    valor_potencial: quanto essa venda valeria em reais, número puro, 0 se não der para saber.
    motivo_bloqueio: um de pediu_preco, sem_vaga, comparando, checkout_abandonado, sem_resposta, outro.
    acao_sugerida: o que fazer no follow-up, em até 8 palavras.
    Nunca invente valor: se o preço não aparece na conversa, use 0.
  SYSTEM

  def reader_prompt
    "Conversa:\n#{transcript}"
  end

  # Bounded so a long thread cannot turn a cheap classifier call into an
  # expensive one.
  TRANSCRIPT_LIMIT = 40
  TRANSCRIPT_MAX_CHARS = 6000

  def transcript
    @transcript ||= @conversation.messages
                                 .where(message_type: %i[incoming outgoing], private: false)
                                 .reorder(created_at: :desc, id: :desc).limit(TRANSCRIPT_LIMIT)
                                 .reverse
                                 .map { |m| "#{m.incoming? ? 'Cliente' : 'Atendente'}: #{m.content}" }
                                 .join("\n").truncate(TRANSCRIPT_MAX_CHARS)
  end

  def parse_reading(content)
    json = content.to_s[/\{.*\}/m]
    return nil if json.blank?

    JSON.parse(json)
  rescue JSON::ParserError
    nil
  end

  def upsert(temperature, reading)
    opportunity = Ai::LeadOpportunity.find_or_initialize_by(conversation_id: @conversation.id)
    opportunity.assign_attributes(
      identity.merge(scoring(temperature, reading))
    )
    opportunity.save!
    opportunity
  end

  def identity
    {
      ai_assistant: @assistant, account: @conversation.account,
      contact_id: @conversation.contact_id, last_seen_at: last_activity_at
    }
  end

  def scoring(temperature, reading)
    reading ||= {}
    {
      temperature: temperature,
      interest: reading['interesse'].presence&.to_s&.truncate(120),
      potential_brl: reading['valor_potencial'].to_f.clamp(0, 1_000_000),
      block_reason: normalised_block_reason(reading['motivo_bloqueio']),
      suggested_action: reading['acao_sugerida'].presence&.to_s&.truncate(120),
      signals: signals(reading)
    }
  end

  def normalised_block_reason(value)
    Ai::LeadOpportunity::BLOCK_REASONS.include?(value.to_s) ? value.to_s : 'outro'
  end

  # Stored so the operator can see WHY a lead scored what it scored. A number
  # nobody can explain should never drive a follow-up campaign.
  def signals(reading)
    {
      'asked_price' => customer_text.match?(PRICE_ASK),
      'asked_schedule' => customer_text.match?(SCHEDULE_ASK),
      'abandoned_checkout' => abandoned_checkout?,
      'returning_customer' => returning_customer?,
      'decay_points' => decay_points,
      'reading' => reading.slice('intencao_compra', 'urgencia', 'objecao_forte')
    }
  end

  def customer_text
    @customer_text ||= texts(:incoming)
  end

  def agent_text
    @agent_text ||= texts(:outgoing)
  end

  def texts(kind)
    @conversation.messages.where(message_type: kind, private: false)
                 .reorder(created_at: :desc, id: :desc).limit(TRANSCRIPT_LIMIT)
                 .filter_map(&:content).join(' ')
  end
end
