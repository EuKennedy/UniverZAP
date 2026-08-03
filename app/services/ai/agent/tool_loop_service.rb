# Runs the Claude tool-use loop: ask Claude → if it wants tools, execute them
# and feed the results back → repeat until Claude returns a final text reply
# (or the iteration cap is hit). Returns the same shape as ClaudeService#chat.
#
# `tool_executor` must respond to `call(name, input) -> String` (the
# tool_result content). Used by the autopilot to let Claude check the salon
# agenda and create appointments mid-conversation.
class Ai::Agent::ToolLoopService
  MAX_ITERATIONS = 6

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
    last = nil
    MAX_ITERATIONS.times do
      last = run_turn
      return last if Array(last[:tool_uses]).empty?

      feed_tool_results(last)
    end
    log_max_iterations
    last
  end

  private

  def run_turn
    response = claude.chat(
      messages: @messages, system: @system, conversation: @conversation,
      phase: @phase, tools: @tools, log_context: @log_context
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
