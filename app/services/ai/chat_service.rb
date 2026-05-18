class Ai::ChatService
  CHARACTER_BUDGET = 32_000

  def initialize(thread:, user_message:)
    @thread = thread
    @assistant = thread.ai_assistant
    @user_message = user_message.to_s.strip
  end

  def perform
    raise Ai::ClaudeService::Error, 'No AI assistant assigned to this thread' if @assistant.nil?
    raise Ai::ClaudeService::Error, 'Empty message' if @user_message.blank?

    persisted_user = persist_user_message
    response = Ai::ClaudeService.new(assistant: @assistant).chat(
      messages: build_messages,
      system: build_system_prompt,
      conversation: @thread.conversation,
      phase: 'copilot_chat'
    )
    assistant_msg = persist_assistant_message(response)
    @thread.touch_activity!

    { user_message: persisted_user, assistant_message: assistant_msg, content: response[:content], model: response[:model] }
  end

  private

  def persist_user_message
    @thread.chat_messages.create!(role: 'user', content: @user_message)
  end

  def persist_assistant_message(response)
    @thread.chat_messages.create!(
      role: 'assistant',
      content: response[:content].to_s,
      model: response[:model]
    )
  end

  def build_system_prompt
    [
      "Você é #{@assistant.name}, copiloto interno do atendente. Ajude a esclarecer dúvidas, redigir respostas e analisar a conversa atual.",
      tone_instruction,
      'Responda em português brasileiro com frases curtas e claras. Não use markdown excessivo. Não se identifique como IA.',
      conversation_snapshot,
      knowledge_snippets
    ].compact.join("\n\n")
  end

  def tone_instruction
    {
      'friendly' => 'Tom amigável e próximo.',
      'formal' => 'Tom formal e respeitoso.',
      'sales' => 'Tom comercial, foco em conversão.',
      'support' => 'Tom de suporte, foco em resolver.',
      'concierge' => 'Tom premium e atencioso.'
    }[@assistant.tone]
  end

  def conversation_snapshot
    return nil if @thread.conversation.nil?

    lines = @thread.conversation
                   .messages
                   .where(message_type: %i[incoming outgoing])
                   .where(private: false)
                   .order(created_at: :desc)
                   .limit(40)
                   .reverse
                   .filter_map { |m| format_snapshot_line(m) }
    return nil if lines.empty?

    "Conversa atual com o cliente (mais recente por último):\n#{lines.join("\n")}"
  end

  def format_snapshot_line(message)
    content = message.content_for_llm.to_s.strip
    return nil if content.blank?

    "#{message.incoming? ? 'Cliente' : 'Atendente'}: #{content}"
  end

  def knowledge_snippets
    chunks = @assistant.trainings.ready.limit(8).pluck(:title, :content)
    return nil if chunks.empty?

    bullets = chunks.map { |title, content| "- #{title}: #{content.to_s.truncate(280)}" }.join("\n")
    "Base de conhecimento:\n#{bullets}"
  end

  def build_messages
    history = @thread.recent_messages_for_llm
    history.map { |m| { role: m.role, content: m.content.to_s } }
  end
end
