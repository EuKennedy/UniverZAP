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
  MAX_STEPS = 25

  def initialize(message)
    @message = message
    @conversation = message.conversation
    @account = message.account
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
  def self.force_start(chatflow, conversation)
    return if chatflow.start_node.blank?
    return if ChatflowExecution.live.exists?(conversation_id: conversation.id)

    service = allocate
    service.instance_variable_set(:@conversation, conversation)
    service.instance_variable_set(:@account, conversation.account)
    execution = ChatflowExecution.create!(
      account: conversation.account, chatflow: chatflow,
      conversation: conversation, current_node: chatflow.start_node, status: :active
    )
    service.send(:run_chain, execution, chatflow.start_node)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  private

  def live_execution
    ChatflowExecution.live.find_by(conversation_id: @conversation.id)
  end

  # --- starting a new flow -------------------------------------------------

  def start_triggered_flow
    return if autopilot_engaged?

    chatflow = matching_chatflow
    return if chatflow&.start_node.blank?

    execution = ChatflowExecution.create!(
      account: @account, chatflow: chatflow, conversation: @conversation,
      current_node: chatflow.start_node, status: :active
    )
    run_chain(execution, chatflow.start_node)
  rescue ActiveRecord::RecordNotUnique
    nil # a concurrent inbound already opened the live execution
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

  # webhook flows are started externally (POST /chatflows/:id/run), so an
  # inbound message never auto-matches them.
  def trigger_matches?(chatflow)
    case chatflow.trigger_type
    when 'on_first_message' then first_message_trigger?(chatflow)
    when 'keyword' then keyword_hit?(chatflow)
    when 'any_message' then true
    else false
    end
  end

  # The first-message trigger fires on the conversation's first inbound
  # message. A `cooldown` restart rule lets it fire again once enough hours
  # have passed since the last run — for recurring touchpoints.
  def first_message_trigger?(chatflow)
    return true if first_inbound_message?

    restart = chatflow.trigger_config['restart'] || {}
    return false unless restart['mode'] == 'cooldown'

    cooldown_elapsed?(chatflow, restart['hours'])
  end

  def cooldown_elapsed?(chatflow, hours)
    window = (hours.to_i.positive? ? hours.to_i : 24).hours
    last_run = chatflow.executions.where(conversation_id: @conversation.id).maximum(:updated_at)
    last_run.nil? || last_run < window.ago
  end

  def first_inbound_message?
    @conversation.messages.incoming.where.not(id: @message.id).none?
  end

  def keyword_hit?(chatflow)
    body = @message.content.to_s.downcase
    chatflow.keywords.any? { |keyword| body.include?(keyword) }
  end

  # --- advancing a waiting flow -------------------------------------------

  def advance_from_reply(execution)
    node = execution.current_node
    return complete(execution) if node.blank?

    option = Chatflow::ReplyMatcher.new(node, @message.content).match
    return reprompt(execution, node) if option.nil?

    record_selection(execution, node, option)
    edge = node.outgoing_edges.find_by(source_handle: option['value'])
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
    steps = 0
    while node.present? && steps < MAX_STEPS
      result = Chatflow::NodeRunnerService.new(execution, node).run
      steps += 1

      return execution.update!(status: :waiting_input, current_node: node) if result == :wait
      return complete(execution) if result == :stop

      node = advance_to_next(execution, node)
    end
    complete(execution) if node.blank? || steps >= MAX_STEPS
  end

  def advance_to_next(execution, node)
    edge = node.outgoing_edges.find_by(source_handle: 'default')
    return nil if edge.blank?

    next_node = node_in_flow(execution, edge.target_node_id)
    execution.update!(current_node: next_node) if next_node.present?
    next_node
  end

  def node_in_flow(execution, node_id)
    execution.chatflow.nodes.find_by(id: node_id)
  end

  def complete(execution)
    execution.update!(status: :completed, current_node: nil)
  end
end
