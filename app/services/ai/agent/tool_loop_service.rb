# Runs the Claude tool-use loop: ask Claude → if it wants tools, execute them
# and feed the results back → repeat until Claude returns a final text reply
# (or the iteration cap is hit). Returns the same shape as ClaudeService#chat.
#
# `tool_executor` must respond to `call(name, input) -> String` (the
# tool_result content). Used by the autopilot to let Claude check the salon
# agenda and create appointments mid-conversation.
class Ai::Agent::ToolLoopService
  MAX_ITERATIONS = 6

  def initialize(assistant:, conversation:, messages:, system:, tools:, tool_executor:, phase: 'autopilot') # rubocop:disable Metrics/ParameterLists
    @assistant = assistant
    @conversation = conversation
    @messages = messages.map { |m| { role: m[:role], content: m[:content] } }
    @system = system
    @tools = tools
    @executor = tool_executor
    @phase = phase
  end

  def perform
    claude = Ai::ClaudeService.new(assistant: @assistant)
    last = nil

    MAX_ITERATIONS.times do
      last = claude.chat(
        messages: @messages, system: @system, conversation: @conversation,
        phase: @phase, tools: @tools
      )
      tool_uses = last[:tool_uses] || []
      return last if tool_uses.empty?

      assistant_blocks = last[:raw]&.dig('content') || []
      @messages << { role: 'assistant', content: assistant_blocks }
      @messages << { role: 'user', content: tool_uses.map { |tu| tool_result_block(tu) } }
    end

    Rails.logger.warn(
      "[Athenas agent] tool loop hit MAX_ITERATIONS conv=#{@conversation&.display_id} assistant=#{@assistant.id}"
    )
    last || { content: '', tool_uses: [], stop_reason: 'max_iterations' }
  end

  private

  def tool_result_block(tool_use)
    {
      type: 'tool_result',
      tool_use_id: tool_use['id'],
      content: @executor.call(tool_use['name'], tool_use['input'])
    }
  end
end
