# O copiloto interno: o agente que o ATENDENTE abre no widget para pedir ajuda.
#
# Ele usa exatamente as mesmas ferramentas que o agente usa falando com o
# cliente. Antes chamava Ai::ClaudeService#chat direto, sem `tools:` e sem loop,
# e o resultado era o mesmo agente que monta carrinho e consulta rastreio na
# conversa ficar cego assim que o atendente abria o widget — perguntava o código
# de rastreio em vez de consultar, porque não tinha com o quê.
#
# O que ele NÃO compartilha com o autopiloto é a persona: ver `role_lock`.
class Ai::ChatService
  # Retrieval ranqueado por relevância, o mesmo do autopiloto. Antes eram os 8
  # primeiros documentos truncados em 280 caracteres cada, sem ordem nenhuma:
  # uma tabela de preço grande entrava pelo começo e o preço perguntado ficava
  # de fora.
  include Ai::KnowledgeGrounding

  CHARACTER_BUDGET = 32_000

  def initialize(thread:, user_message:)
    @thread = thread
    @assistant = thread.ai_assistant
    # Ai::KnowledgeGrounding lê @conversation direto. É a conversa do CLIENTE
    # que o atendente está atendendo, e ela pode não existir: uma thread do
    # widget aberta fora de uma conversa é legítima.
    @conversation = thread.conversation
    @user_message = user_message.to_s.strip
  end

  def perform
    raise Ai::ClaudeService::Error, 'No AI assistant assigned to this thread' if @assistant.nil?
    raise Ai::ClaudeService::Error, 'Empty message' if @user_message.blank?

    persisted_user = persist_user_message
    response = generate_response
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
      role_lock,
      'Responda em português brasileiro com frases curtas e claras. Não use markdown excessivo.',
      conversation_snapshot,
      knowledge_snippets
    ].compact.join("\n\n")
  end

  # Hard role-lock. Without this the copilot inherits the customer-facing
  # sales persona (tone='sales' + the trainings playbook) and starts
  # pitching the AGENT as if they were a customer — e.g. answering a bare
  # "olá, consegue me ajudar?" with a revenda sales pitch it hallucinated
  # from a random training doc. The copilot talks to the agent, never to
  # the customer, and must not assume a topic.
  def role_lock
    <<~ROLE.strip
      Você é #{@assistant.name}, o COPILOTO INTERNO do atendente humano. Você conversa COM O ATENDENTE (um colega da equipe), NUNCA com o cliente final.

      Regras inegociáveis:
      • NÃO faça pitch de vendas nem escreva como se estivesse respondendo o cliente — só redija um rascunho de resposta ao cliente se o atendente pedir isso explicitamente.
      • NÃO presuma o assunto. Se o atendente apenas cumprimentar ("oi", "consegue me ajudar?"), pergunte de forma objetiva no que pode ajudar. NUNCA invente que ele perguntou sobre um produto, revenda ou qualquer tópico.
      • A base de conhecimento e o histórico abaixo são apenas CONSULTA, usados quando o atendente pedir algo específico. NÃO os trate como o assunto da mensagem atual.

      Ajude a esclarecer dúvidas, redigir respostas e analisar a conversa do cliente quando solicitado.
    ROLE
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

    header = 'Conversa que o atendente está atendendo com o CLIENTE ' \
             '(apenas contexto para consulta — NÃO é você conversando, ' \
             'NÃO responda a ela por conta própria):'
    "#{header}\n#{lines.join("\n")}"
  end

  def format_snapshot_line(message)
    content = message.content_for_llm.to_s.strip
    return nil if content.blank?

    "#{message.incoming? ? 'Cliente' : 'Atendente'}: #{content}"
  end

  def build_messages
    history = @thread.recent_messages_for_llm
    history.map { |m| { role: m.role, content: m.content.to_s } }
  end

  # Com ferramenta, a resposta passa pelo loop; sem, é uma chamada só. A
  # diferença importa porque o loop cobra por iteração, e um agente sem
  # ferramenta nenhuma não deve pagar a máquina de nada.
  def generate_response
    executor = toolset.executor
    return plain_chat unless executor.any?

    Ai::Agent::ToolLoopService.new(
      assistant: @assistant, conversation: @conversation,
      messages: build_messages, system: build_system_prompt,
      tools: executor.definitions, tool_executor: executor, phase: 'copilot_chat'
    ).perform
  end

  def plain_chat
    Ai::ClaudeService.new(assistant: @assistant).chat(
      messages: build_messages, system: build_system_prompt,
      conversation: @conversation, phase: 'copilot_chat'
    )
  end

  # A thread do widget pode não ter conversa. O Toolset trata isso: entrega as
  # ferramentas customizadas assim mesmo e deixa a agenda de fora, porque
  # agendar sem contato é o agendamento órfão que CustomerPhone documenta.
  def toolset
    @toolset ||= Ai::Agent::Toolset.new(assistant: @assistant, conversation: @conversation)
  end

  # A pergunta que importa é a que o ATENDENTE acabou de fazer, não a última
  # mensagem do cliente: ele abre o widget justamente para perguntar outra coisa.
  def knowledge_query
    @user_message
  end

  def latest_user_message
    @user_message
  end
end
