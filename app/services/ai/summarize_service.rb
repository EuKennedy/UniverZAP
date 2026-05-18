class Ai::SummarizeService
  HISTORY_LIMIT = 80

  def initialize(conversation:, assistant: nil)
    @conversation = conversation
    @assistant = assistant || conversation.ai_assistant || conversation.inbox.ai_assistant
  end

  def perform
    raise Ai::ClaudeService::Error, 'No AI assistant assigned to this conversation' if @assistant.nil?
    raise Ai::ClaudeService::Error, 'Conversation has no messages to summarize' if transcript.blank?

    Ai::ClaudeService.new(assistant: @assistant).chat(
      messages: [{ role: 'user', content: transcript }],
      system: system_prompt,
      conversation: @conversation,
      phase: 'summarize'
    )
  end

  private

  def system_prompt
    <<~PROMPT.strip
      Você é um especialista em resumir conversas de atendimento.
      Gere um resumo executivo da conversa abaixo em português brasileiro.
      Foque em: motivo do contato, pontos principais discutidos, decisões tomadas, próximos passos.
      Não invente informação. Não use markdown. Máximo 6 frases curtas.
      Não se identifique como IA.
    PROMPT
  end

  def transcript
    @transcript ||= build_transcript
  end

  def build_transcript
    @conversation.messages
                 .where(message_type: %i[incoming outgoing])
                 .where(private: false)
                 .order(created_at: :desc)
                 .limit(HISTORY_LIMIT)
                 .reverse
                 .filter_map { |m| format_line(m) }
                 .join("\n")
  end

  def format_line(message)
    content = message.content_for_llm.to_s.strip
    return nil if content.blank?

    speaker = message.incoming? ? 'Cliente' : 'Atendente'
    "#{speaker}: #{content}"
  end
end
