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

  STYLE_RULE = 'Responda em português brasileiro com frases curtas e claras. Não use markdown excessivo.'.freeze

  def initialize(thread:, user_message:)
    @thread = thread
    @assistant = thread.ai_assistant
    # Ai::KnowledgeGrounding lê @conversation direto. É a conversa do CLIENTE
    # que o atendente está atendendo, e ela pode não existir: uma thread do
    # widget aberta fora de uma conversa é legítima.
    @conversation = thread.conversation
    @user_message = user_message.to_s.strip
    @turn_cents = 0.0
    @turn_tokens = [0, 0]
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

  # Os números do turno vão junto da resposta. O painel mostra tokens e reais em
  # letra pequena embaixo do que o Guia respondeu — sem isso, quem paga a conta
  # só descobre o custo no fim do mês, quando não dá mais para relacionar o
  # número a nenhuma pergunta.
  def persist_assistant_message(response)
    @thread.chat_messages.create!(
      role: 'assistant',
      content: response[:content].to_s,
      model: response[:model],
      input_tokens: @turn_tokens.first,
      output_tokens: @turn_tokens.last,
      cost_brl: (@turn_cents / 100.0).round(4),
      cost_usd: response[:invocation]&.cost_usd.to_f
    )
  end

  # Um turno com ferramenta são VÁRIAS chamadas, então o preço é a soma delas —
  # ler só a última contaria a chamada mais barata e esconderia o loop inteiro.
  def record_usage(loop_service: nil, response: nil)
    if loop_service
      @turn_cents = loop_service.spent_cents
      @turn_tokens = loop_service.spent_tokens
    else
      invocation = response&.dig(:invocation)
      @turn_cents = invocation&.cost_brl.to_f * 100
      @turn_tokens = [invocation&.input_tokens.to_i, invocation&.output_tokens.to_i]
    end
    response
  end

  # Segmentos, e não uma string: Ai::ClaudeService manda string crua SEM cache
  # nenhum, e o loop reenvia o prompt inteiro a cada iteração.
  #
  # A ordem decide o preço. Ai::ClaudeService cacheia TUDO menos o último
  # segmento, então o que é igual em toda pergunta tem que vir antes dele.
  #
  # Para o copiloto o último é o contexto da conversa, que muda a cada turno e
  # por isso não poderia ser cacheado mesmo. Para o Guia não existe nada volátil:
  # o manual é o mesmo sempre, então ele vai para o bloco cacheado e quem sobra
  # na cauda é a regra de estilo, que tem duas linhas — pagar preço cheio por ela
  # é irrelevante, e pagar preço cheio pelo manual em toda pergunta não era.
  def build_system_prompt
    return [role_lock, manual, STYLE_RULE].compact if wiki?

    [role_lock, STYLE_RULE, dynamic_context].compact
  end

  # O papel de quem está falando. Dois agentes diferentes moram neste serviço: o
  # copiloto, que fala da conversa do CLIENTE com a atendente, e o Guia, que fala
  # do PRODUTO com quem o usa. O prompt do Guia é escrito em Ai::Wiki::Seeder e
  # era descartado aqui — ele recebia o role_lock do copiloto e era instruído a
  # falar de uma conversa de cliente que não existe na tela dele.
  def role_lock
    wiki? ? @assistant.system_prompt.to_s : copilot_role_lock
  end

  def wiki?
    @assistant.purpose == 'wiki'
  end

  # O manual INTEIRO, e no prefixo estável. São 18 seções que somam ~7.400
  # caracteres, e a recuperação devolvia ~3.300 deles — dos quais uns 2.700 eram
  # seções irrelevantes, porque o ranking não tem limiar e preenche as 8 vagas de
  # qualquer jeito. Mandar tudo custa pouco mais em token cru e MUITO menos na
  # conta: o manual é igual em toda pergunta, então entra no bloco cacheado a um
  # décimo do preço, enquanto o recuperado mudava a cada turno e era recomprado
  # inteiro. De quebra some o motivo de o Guia não saber algo que está escrito.
  def dynamic_context
    [conversation_snapshot, knowledge_snippets].compact.join("\n\n").presence
  end

  def manual
    docs = @assistant.trainings.ready.order(:id).map { |doc| "## #{doc.title}\n#{doc.content}" }
    return nil if docs.empty?

    "DOCUMENTAÇÃO DO UNIVERZAP:\n\n#{docs.join("\n\n")}"
  end

  # Hard role-lock. Without this the copilot inherits the customer-facing
  # sales persona (tone='sales' + the trainings playbook) and starts
  # pitching the AGENT as if they were a customer — e.g. answering a bare
  # "olá, consegue me ajudar?" with a revenda sales pitch it hallucinated
  # from a random training doc. The copilot talks to the agent, never to
  # the customer, and must not assume a topic.
  def copilot_role_lock
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

    loop_service = Ai::Agent::ToolLoopService.new(
      assistant: @assistant, conversation: @conversation,
      messages: build_messages, system: build_system_prompt,
      tools: executor.definitions, tool_executor: executor, phase: phase
    )
    response = loop_service.perform
    record_usage(loop_service: loop_service)
    response
  end

  def plain_chat
    record_usage(
      response: Ai::ClaudeService.new(assistant: @assistant).chat(
        messages: build_messages, system: build_system_prompt,
        conversation: @conversation, phase: phase
      )
    )
  end

  # A thread do widget pode não ter conversa. O Toolset trata isso: entrega as
  # ferramentas customizadas assim mesmo e deixa a agenda de fora, porque
  # agendar sem contato é o agendamento órfão que CustomerPhone documenta.
  # O copiloto é uso de IA do cliente e entra na conta dele. O Guia é suporte ao
  # produto, e Ai::Invocation::UNBILLED_PHASES tira wiki_chat do débito — estava
  # tudo indo como copilot_chat, então o Guia vinha cobrando do tenant apesar da
  # fase existir justamente para isso não acontecer.
  def phase
    wiki? ? 'wiki_chat' : 'copilot_chat'
  end

  def toolset
    @toolset ||= Ai::Agent::Toolset.new(
      assistant: @assistant, conversation: @conversation, user: @thread.user
    )
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
