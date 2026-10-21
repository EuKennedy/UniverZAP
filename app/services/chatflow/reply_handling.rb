# Como uma execução parada numa etapa reage à mensagem do cliente: menu,
# confirmação, formulário, pergunta com captura e espera. Incluído no
# Chatflow::EngineService (usa follow/complete/record_selection dele).
module Chatflow::ReplyHandling
  private

  REPLY_HANDLERS = {
    'confirmation' => :advance_from_confirmation,
    'send_flow' => :advance_from_flow,
    'question' => :advance_from_question,
    'wait' => :advance_from_wait,
    'typing' => :ignore_reply
  }.freeze

  def advance_from_reply(execution)
    node = execution.current_node
    return complete(execution) if node.blank?

    handler = REPLY_HANDLERS[node.kind]
    return send(handler, execution, node) if handler

    option = Chatflow::ReplyMatcher.new(node, @message.content).match
    return reprompt(execution, node) if option.nil?

    record_selection(execution, node, option)
    follow(execution, node, option['value'])
  end

  # A Confirmação casa por LISTA de palavras-chave e tem uma saída para quando
  # nada casa — diferente do menu, que repergunta para sempre. Um cliente que
  # escreveu um desabafo em vez de "sim" ficaria preso recebendo a mesma
  # pergunta até o fim dos tempos.
  def advance_from_confirmation(execution, node)
    handle = Chatflow::ConfirmationMatcher.new(node, @message.content).match
    return confirmation_retry(execution, node) if handle.nil?

    record_selection(execution, node, 'value' => handle, 'label' => handle)
    follow(execution, node, handle)
  end

  # A resposta do formulário (deste formulário, não de um antigo) segue pela
  # saída normal. Texto digitado sai pelo `fallback` quando ele está ligado;
  # sem ligação, o fluxo continua esperando o formulário — o cliente ainda pode
  # preenchê-lo, e encerrar aqui o deixaria sem nada.
  def advance_from_flow(execution, node)
    response = @message.content_attributes['flow_response']
    if response.present? && response['flow_id'].to_s == node.config['whatsapp_flow_id'].to_s
      record_selection(execution, node, 'value' => 'default', 'label' => 'respondeu')
      return follow(execution, node, 'default')
    end
    return unless node.outgoing_edges.exists?(source_handle: ChatflowNode::FALLBACK)

    record_selection(execution, node, 'value' => ChatflowNode::FALLBACK, 'label' => 'digitou')
    follow(execution, node, ChatflowNode::FALLBACK)
  end

  # O robô está "digitando": a mensagem dela fica para a próxima etapa ler.
  def ignore_reply(_execution, _node)
    nil
  end

  # Pergunta com captura: resposta válida grava o atributo e segue; inválida
  # manda a mensagem de erro, e depois de N tentativas sai pela porta
  # `invalid` (ou encerra, se ela não estiver ligada) — nunca prende o cliente.
  def advance_from_question(execution, node)
    capture = Chatflow::AnswerCapture.new(node, @conversation)
    value = capture.parse(@message.content)
    return question_retry(execution, node) if value.nil?

    key = capture.save(value)
    answers = execution.context['answers'].to_h.merge((key || node.id.to_s) => value)
    execution.update!(context: execution.context.merge('answers' => answers))
    record_selection(execution, node, 'value' => 'default', 'label' => value.to_s)
    follow(execution, node, 'default')
  end

  def question_retry(execution, node)
    tries = node_tries(execution, node) + 1
    record_node_tries(execution, node, tries)
    max = (node.config['max_attempts'].presence || 3).to_i.clamp(1, 10)
    if tries >= max
      record_selection(execution, node, 'value' => ChatflowNode::INVALID, 'label' => 'resposta inválida')
      return follow(execution, node, ChatflowNode::INVALID)
    end

    Chatflow::NodeRunnerService.new(execution, node).resend_question_error
  end

  # O cliente escreveu durante a Espera. `keep` ignora e o relógio segue;
  # `branch` sai pela porta "Respondeu"; o padrão (`stop`) encerra o fluxo —
  # a pessoa voltou a falar, o lembrete programado perdeu o sentido.
  def advance_from_wait(execution, node)
    mode = node.config['on_reply'].presence || 'stop'
    return if mode == 'keep'
    return unless execution.claim_timer!

    execution.reload
    return complete(execution) unless mode == 'branch'

    record_selection(execution, node, 'value' => ChatflowNode::REPLIED, 'label' => 'respondeu')
    follow(execution, node, ChatflowNode::REPLIED)
  end

  # Duas tentativas e sai pela porta de NÃO RESOLVIDO. Errar para o lado de
  # mandar para um humano é o erro barato; o contrário abandona um cliente que
  # continua com problema dentro de um robô que não o entende.
  def confirmation_retry(execution, node)
    tries = confirmation_tries(execution, node) + 1
    record_confirmation_tries(execution, node, tries)

    if tries > ChatflowNode::MAX_CONFIRMATION_RETRIES
      record_selection(execution, node, 'value' => ChatflowNode::UNRESOLVED, 'label' => 'sem resposta')
      return follow(execution, node, ChatflowNode::UNRESOLVED)
    end

    Chatflow::NodeRunnerService.new(execution, node).resend_confirmation
  end

  def confirmation_tries(execution, node)
    execution.context.dig('confirmation_tries', node.id.to_s).to_i
  end

  def record_confirmation_tries(execution, node, tries)
    counters = execution.context['confirmation_tries'].to_h.merge(node.id.to_s => tries)
    execution.update!(context: execution.context.merge('confirmation_tries' => counters))
  end

  def node_tries(execution, node)
    execution.context.dig('node_tries', node.id.to_s).to_i
  end

  def record_node_tries(execution, node, tries)
    counters = execution.context['node_tries'].to_h.merge(node.id.to_s => tries)
    execution.update!(context: execution.context.merge('node_tries' => counters))
  end
end
