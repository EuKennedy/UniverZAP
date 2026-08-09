# Runs the Claude tool-use loop: ask Claude → if it wants tools, execute them
# and feed the results back → repeat until Claude returns a final text reply
# (or the iteration cap is hit). Returns the same shape as ClaudeService#chat.
#
# `tool_executor` must respond to `call(name, input) -> String` (the
# tool_result content). Used by the autopilot to let Claude check the salon
# agenda and create appointments mid-conversation.
class Ai::Agent::ToolLoopService
  MAX_ITERATIONS = 6

  # Wall-clock ceiling for one whole turn, enforced in ONE place.
  #
  # Counting iterations was never a time limit: each one is a full Claude
  # generation plus however long the customer's endpoint takes to answer. Now
  # that the Anthropic call is streamed and no longer dies at 30s, nothing else
  # bounds a turn, and Sidekiq runs 10 threads across every queue in strict
  # priority, so a handful of slow turns can starve :critical. 90s is roughly
  # three unhurried iterations and still inside what someone waiting on
  # WhatsApp will tolerate.
  TURN_BUDGET_SECONDS = 90

  def initialize(assistant:, conversation:, messages:, system:, tools:, tool_executor:, phase: 'autopilot', log_context: nil) # rubocop:disable Metrics/ParameterLists
    @assistant = assistant
    @conversation = conversation
    @messages = messages.map { |m| { role: m[:role], content: m[:content] } }
    @system = system
    @tools = tools
    @executor = tool_executor
    @phase = phase
    # Carried on every iteration, not just the last: a tool-using turn bills
    # several calls and each one must be auditable on its own.
    @log_context = log_context
  end

  def perform
    @deadline = monotonic_now + TURN_BUDGET_SECONDS
    last = nil
    MAX_ITERATIONS.times do
      last = run_turn
      return last if Array(last[:tool_uses]).empty?

      feed_tool_results(last)
      return final_answer if out_of_budget?
    end
    log_max_iterations
    last
  end

  private

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def out_of_budget?
    monotonic_now >= @deadline
  end

  # The budget ran out with tool results already in hand. One last call with
  # tool_choice `none`: Claude cannot ask for another round, so it has to answer
  # with what it has. A degraded answer beats the silence the customer got
  # before. The tools stay in the payload because the transcript already
  # contains tool_use blocks and Anthropic rejects those without their
  # definitions.
  def final_answer
    log_budget_exhausted
    claude.chat(
      messages: @messages, system: @system, conversation: @conversation,
      phase: @phase, tools: @tools, tool_choice: { type: 'none' },
      log_context: @log_context, cache_messages: true
    )
  end

  def log_budget_exhausted
    Rails.logger.warn(
      "[Athenas agent] turn budget #{TURN_BUDGET_SECONDS}s exhausted, forcing final answer " \
      "conv=#{@conversation&.display_id} assistant=#{@assistant.id}"
    )
  end

  def run_turn
    response = claude.chat(
      messages: @messages, system: @system, conversation: @conversation,
      phase: @phase, tools: @tools, log_context: @log_context,
      # Each iteration re-sends everything the previous ones did, plus the tool
      # results they collected — the list grows several-fold across a loop. They
      # run seconds apart, so caching the prefix turns that re-send into a read
      # at a tenth of the price.
      cache_messages: true
    )
    @log_context = follow_up_context
    response
  end

  # Later iterations of the same turn reuse the identical system prompt. Storing
  # that snapshot again on every iteration would multiply the heaviest column in
  # the log by the loop length and tell a reviewer nothing new. The rows still
  # carry the trigger message and open as `pending`, so nothing escapes the
  # audit — only the duplicate text is dropped.
  def follow_up_context
    return nil if @log_context.blank?

    @log_context.merge(skip_snapshot: true)
  end

  def claude
    @claude ||= Ai::ClaudeService.new(assistant: @assistant)
  end

  def feed_tool_results(response)
    @messages << { role: 'assistant', content: response[:raw]&.dig('content') || [] }
    @messages << { role: 'user', content: Array(response[:tool_uses]).map { |tu| tool_result_block(tu) } }
  end

  def log_max_iterations
    Rails.logger.warn(
      "[Athenas agent] tool loop hit MAX_ITERATIONS conv=#{@conversation&.display_id} assistant=#{@assistant.id}"
    )
  end

  def tool_result_block(tool_use)
    {
      type: 'tool_result',
      tool_use_id: tool_use['id'],
      content: @executor.call(tool_use['name'], tool_use['input'])
    }
  end
end
