class Ai::SuggestReplyService
  # Mirrors the autopilot window so suggestion + autopilot see the
  # same conversation slice. 12 was leaving Claude blind to early
  # context on longer threads (qualification questions get forgotten
  # halfway through and the suggested reply restarts the flow).
  HISTORY_LIMIT = 25

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

    response
  end

  private

  def build_system_prompt
    [
      'Você está redigindo a próxima mensagem que o(a) atendente humano(a) irá enviar para o cliente.',
      "Persona do atendente: #{@assistant.name}, #{@assistant.role}.",
      @assistant.system_prompt.presence,
      tone_instruction,
      knowledge_snippets,
      continuity_rules
    ].compact.join("\n\n")
  end

  # Continuity guardrails identical to the autopilot path. Without them
  # Claude greets / re-introduces / re-asks for hair type every turn —
  # exactly what surfaced in the Lizzon screenshots.
  def continuity_rules
    history_has_replies = @conversation.messages
                                       .where(message_type: :outgoing, private: false)
                                       .exists?
    [
      'REGRAS CRÍTICAS DE CONTINUIDADE (siga literalmente):',
      ('• Esta é uma conversa em ANDAMENTO. NUNCA reinicie o atendimento.' if history_has_replies),
      ('• PROIBIDO cumprimentar ou se apresentar de novo se o atendente já falou no histórico.' if history_has_replies),
      ('• PROIBIDO repetir perguntas já respondidas pelo cliente. Leia o histórico antes de perguntar qualquer coisa.' if history_has_replies),
      '• Continue exatamente de onde a última mensagem do assistant parou.',
      '• Use APENAS as mensagens do histórico abaixo como contexto. Não invente histórico que não está visível.',
      '• Se o cliente trouxe novas informações nesta mensagem, USE-AS imediatamente — não confirme que recebeu, aja.',
      '• Gere APENAS o corpo da próxima mensagem do atendente. Português brasileiro, frases curtas, sem markdown, sem prefixos, sem aspas, sem se identificar como IA.',
      '• Se faltar alguma informação que NÃO está no histórico, pergunte UMA coisa por vez de forma natural.'
    ].compact.join("\n")
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
