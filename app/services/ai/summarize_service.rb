class Ai::SummarizeService
  HISTORY_LIMIT = 80

  def initialize(conversation:, assistant: nil)
    @conversation = conversation
    @assistant = assistant || conversation.ai_assistant || conversation.inbox.ai_assistant
  end

  def perform
    raise Ai::ClaudeService::Error, 'No AI assistant assigned to this conversation' if @assistant.nil?
    raise Ai::ClaudeService::Error, 'Conversation has no messages to summarize' if transcript.blank?

    response = Ai::ClaudeService.new(assistant: @assistant).chat(
      messages: [{ role: 'user', content: transcript }],
      system: system_prompt,
      conversation: @conversation,
      phase: 'summarize'
    )

    if response[:content].to_s.strip.empty?
      Rails.logger.warn(
        "[Athenas] summarize empty content assistant=#{@assistant.id} " \
        "conv=#{@conversation.display_id} stop=#{response[:stop_reason]}"
      )
      raise Ai::ClaudeService::Error, 'Assistant returned empty response'
    end

    response
  end

  private

  def system_prompt
    # The summary is consumed by AutopilotReplyService as the "memory"
    # of facts the customer has shared. A narrative summary loses the
    # specifics (cabelo cacheado, química sim, objetivo alisamento) —
    # exactly the things the autopilot must NOT re-ask. So we force
    # extraction of structured facts FIRST, then a short narrative.
    <<~PROMPT.strip
      Você analisa conversas de atendimento e extrai os FATOS que o cliente
      já compartilhou. Esse extrato vira a memória do agente para a próxima
      resposta — qualquer fato que você omitir, o agente vai perguntar de
      novo. Seja específico.

      Formato OBRIGATÓRIO (use exatamente esses cabeçalhos, em pt-BR,
      sem markdown):

      FATOS DO CLIENTE:
      - <fato 1 exato com a frase do cliente quando relevante>
      - <fato 2>
      - <...>
      (omita esta seção se o cliente ainda não respondeu nada)

      MOTIVO DO CONTATO:
      <1 frase>

      ESTADO ATUAL:
      <1 frase descrevendo onde a conversa parou — última pergunta aberta,
      próximo passo combinado, pendência>

      Regras:
      - Use as palavras EXATAS do cliente quando possível.
      - Não invente fatos que não aparecem na conversa.
      - Não inclua saudações ou suposições.
      - Máximo 12 linhas no total.
      - Não se identifique como IA.
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
