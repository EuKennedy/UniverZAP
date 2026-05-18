class Ai::SuggestReplyService
  HISTORY_LIMIT = 12

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
      'Leia o histórico abaixo e gere APENAS o texto da resposta que o atendente deve enviar agora. ' \
      'Não cumprimente novamente se o atendente já cumprimentou. ' \
      'Não escreva prefixos como "Atendente:", "Resposta:", aspas, ou explicações. ' \
      'Saída deve ser só o corpo da mensagem em português brasileiro, tom natural, frases curtas. ' \
      'NÃO use markdown. NÃO se identifique como IA.',
      knowledge_snippets
    ].compact.join("\n\n")
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
