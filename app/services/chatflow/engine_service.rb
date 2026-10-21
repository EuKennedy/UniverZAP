# Orchestrates a chatflow against a single inbound message:
#   - a live execution waiting on a menu  -> match the reply, route to the
#     selected option's edge, keep walking the graph;
#   - no live execution                   -> see if a published flow's trigger
#     matches and, if so, start it from the entry node.
#
# Auto-advancing nodes (send message/audio/media, set label) chain forward
# along their `default` edge until the engine hits a menu (wait for input) or
# a terminal/dead-end node (complete). MAX_STEPS guards against cyclic graphs.
class Chatflow::EngineService
  include Chatflow::TriggerChecks
  include Chatflow::ReplyHandling

  MAX_STEPS = 25
  # Quantos "Ir para outro fluxo" seguidos antes de desistir: dois fluxos que
  # apontam um para o outro não podem virar um robô que fala para sempre.
  MAX_GOTO_DEPTH = 5

  def initialize(message, conversation: nil)
    @message = message
    @conversation = conversation || message&.conversation
    @account = @conversation&.account
  end

  def perform
    return if @conversation.blank?

    execution = live_execution
    if execution&.status_waiting_input?
      advance_from_reply(execution)
    elsif execution.nil?
      start_triggered_flow
    end
    # An `active` (mid auto-run) execution ignores concurrent inbound noise.
  end

  # Start a specific flow on a conversation regardless of trigger — used by
  # the webhook trigger endpoint (POST /chatflows/:id/run).
  def self.force_start(chatflow, conversation, context: {})
    new(nil, conversation: conversation).start(chatflow, context: context)
  end

  # O relógio de uma Espera/Digitando venceu: segue pela saída normal. A trava
  # é o `claim_timer!` — se o cliente respondeu no mesmo instante e a resposta
  # já soltou a etapa, o timer não faz nada.
  def self.resume(execution)
    return unless execution.status_waiting_input? && execution.claim_timer!

    execution.reload
    service = new(nil, conversation: execution.conversation)
    service.send(:follow, execution, execution.current_node, 'default')
  end

  # Começa `chatflow` nesta conversa a partir da etapa inicial. Não começa se já
  # há um fluxo vivo ou pausado: um atendente que assumiu não pode ser
  # atropelado por um gatilho que chegou depois.
  def start(chatflow, context: {})
    return if chatflow&.start_node.blank?
    return if ChatflowExecution.live.exists?(conversation_id: @conversation.id)
    return if Chatflow::BotControl.paused?(@conversation)

    execution = ChatflowExecution.create!(
      account: @account, chatflow: chatflow, conversation: @conversation,
      current_node: chatflow.start_node, status: :active, context: context
    )
    run_chain(execution, chatflow.start_node)
    execution
  rescue ActiveRecord::RecordNotUnique
    nil # a concurrent inbound already opened the live execution
  end

  # Para gatilhos que não vêm de mensagem (etiqueta, data, lista): mesmas
  # regras de elegibilidade do gatilho por mensagem — modo de teste só com o
  # número do testador, e nunca por cima do piloto automático da IA.
  def start_from_event(chatflow, context: {})
    return if autopilot_engaged? || !flow_eligible?(chatflow)

    start(chatflow, context: context)
  end

  private

  def live_execution
    ChatflowExecution.live.find_by(conversation_id: @conversation.id)
  end

  # --- starting a new flow -------------------------------------------------

  def start_triggered_flow
    return if autopilot_engaged?

    start(matching_chatflow)
  end

  # Honour the operator's "IA neste chat" switch — never let a flow talk over
  # the AI autopilot on the same conversation.
  def autopilot_engaged?
    attrs = @conversation.additional_attributes || {}
    ActiveModel::Type::Boolean.new.cast(attrs['autopilot_enabled'])
  end

  # Live flows fire for everyone; a flow in test mode fires only for the
  # tester's number (and even while still a draft) so operators can rehearse
  # before publishing.
  def matching_chatflow
    candidates = @account.chatflows
                         .where(inbox_id: [@conversation.inbox_id, nil])
                         .where('status = ? OR test_mode = ?', Chatflow.statuses[:active], true)
    candidates.detect { |chatflow| flow_eligible?(chatflow) && trigger_matches?(chatflow) }
  end

  def flow_eligible?(chatflow)
    return true unless chatflow.test_mode

    digits = chatflow.test_digits
    return false if digits.blank?

    @conversation.contact&.phone_number.to_s.gsub(/\D/, '').include?(digits)
  end

  # Sai do nó pelo handle escolhido. Handle sem ligação desenhada termina a
  # execução em vez de travar: o operador que não ligou aquela ponta decidiu,
  # por omissão, que o fluxo acaba ali.
  def follow(execution, node, handle)
    edge = node.outgoing_edges.find_by(source_handle: handle)
    return complete(execution) if edge.blank?

    execution.update!(status: :active)
    run_chain(execution, node_in_flow(execution, edge.target_node_id))
  end

  def reprompt(execution, node)
    Chatflow::NodeRunnerService.new(execution, node).resend_menu
  end

  def record_selection(execution, node, option)
    selections = Array(execution.context['selections'])
    selections << { 'node_id' => node.id, 'value' => option['value'], 'label' => option['label'] }
    execution.update!(context: execution.context.merge('selections' => selections))
  end

  # --- graph walk ----------------------------------------------------------

  def run_chain(execution, node)
    MAX_STEPS.times do
      return complete(execution) if node.blank?

      node = run_step(execution, node)
      return if node == :halted
    end
    complete(execution)
  end

  # Roda uma etapa e devolve a próxima (ou :halted quando a corrida para ali).
  def run_step(execution, node)
    execution.visit!(node)
    result = Chatflow::NodeRunnerService.new(execution, node).run
    case result
    when :wait then halt { execution.update!(status: :waiting_input, current_node: node) }
    when :stop then halt { complete(execution) }
    when :goto then halt { goto_flow(execution, node) }
    when String
      record_branch(execution, node, result)
      advance_to_next(execution, node, result)
    else
      advance_to_next(execution, node)
    end
  end

  def halt
    yield
    :halted
  end

  def record_branch(execution, node, handle)
    record_selection(execution, node, 'value' => handle, 'label' => handle)
  end

  # Encerra este fluxo e começa o outro na mesma conversa. Só vai para fluxo
  # ativo — ou rascunho quando ESTE está em modo de teste —, para um rascunho
  # nunca falar com cliente de verdade por tabela.
  def goto_flow(execution, node)
    target = @account.chatflows.find_by(id: node.config['chatflow_id'])
    depth = execution.context['goto_depth'].to_i + 1
    complete(execution)
    return if target.blank? || target.id == execution.chatflow_id || depth > MAX_GOTO_DEPTH
    return unless target.status_active? || execution.chatflow.test_mode

    start(target, context: { 'goto_depth' => depth, 'from_chatflow_id' => execution.chatflow_id })
  end

  def advance_to_next(execution, node, handle = 'default')
    edge = node.outgoing_edges.find_by(source_handle: handle)
    return nil if edge.blank?

    next_node = node_in_flow(execution, edge.target_node_id)
    execution.update!(current_node: next_node) if next_node.present?
    next_node
  end

  def node_in_flow(execution, node_id)
    execution.chatflow.nodes.find_by(id: node_id)
  end

  def complete(execution)
    execution.update!(status: :completed, current_node: nil, resume_at: nil)
  end
end
