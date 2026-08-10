# Runs the Claude tool-use loop: ask Claude → if it wants tools, execute them
# and feed the results back → repeat until Claude returns a final text reply
# (or the iteration cap is hit). Returns the same shape as ClaudeService#chat.
#
# `tool_executor` must respond to `call(name, input) -> String` (the
# tool_result content). Used by the autopilot to let Claude check the salon
# agenda and create appointments mid-conversation.
class Ai::Agent::ToolLoopService
  # Raised when the turn insists on ending with a promise to go and look
  # something up. The agent has no "later" — it speaks only when the customer
  # does — so that reply is a conversation that stops dead with the customer
  # waiting for a message nobody will ever send. Silence at least reads as a
  # queue; a broken promise reads as being ghosted mid-sentence, and the caller
  # turns this into a handover to a human.
  class PromiseUnfulfilled < StandardError; end

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

  # Claude routinely writes "deixa eu confirmar o valor certinho" and stops
  # there, with no tool_use block — then adds a qualifying question, because the
  # operator's sales script asks for one. The loop sees an empty tool_uses,
  # calls the turn finished and sends it, and the customer waits for a lookup
  # that was never started: there is no later turn where the agent remembers.
  # The prompt forbids this, but a soft rule is exactly what the loop-breaker
  # and the grounding guard already proved gets overridden by a tenant script.
  ANNOUNCED_LOOKUP = /
    \b(?:deixa\s+eu|vou|já\s+vou)\s+(?:ver|verificar|conferir|consultar|checar|buscar|confirmar|puxar|olhar)
    |\bjá\s+(?:te\s+)?(?:confirmo|retorno|falo|digo|mando|passo)
    |\b(?:um\s+instante|um\s+momento|só\s+um\s+minuto|um\s+minutinho|só\s+um\s+segundo)
  /xi

  # Claude sometimes WRITES the call instead of making it, emitting a literal
  # block of tool-call markup as message text — seen in production on a later
  # iteration, with an invented parameter name to match. Unlike a promise, this
  # is unambiguous and unsalvageable: the customer would be shown raw markup.
  # Forced on ANY iteration, and stripped if the retry fails.
  WRITTEN_TOOL_CALL = %r{<\s*/?\s*(?:tool_uses?|tool_name|antml:invoke|function_calls?)\b}i

  def perform
    @deadline = monotonic_now + TURN_BUDGET_SECONDS
    last = nil
    MAX_ITERATIONS.times do
      last = run_turn
      last = force_tool_use(last) if force_tool_use?(last)
      return finish(last) if Array(last[:tool_uses]).empty?

      feed_tool_results(last)
      return finish(final_answer) if out_of_budget?
    end
    log_max_iterations
    finish(last)
  end

  private

  # Checked on EVERY iteration, not only the first. The old rule assumed a
  # promise made after a tool call had already been kept by that call — but the
  # promise being made NOW is about the next lookup, and there is no next
  # iteration guaranteed to make it. In production the agent called one tool,
  # read a result that did not answer the question, and then said "deixa eu
  # buscar aqui pra você" on the second iteration, which sailed past this check
  # and became the last thing the customer ever heard.
  def force_tool_use?(response)
    return false if @tools.blank? || Array(response[:tool_uses]).any?

    text = response[:content].to_s
    WRITTEN_TOOL_CALL.match?(text) || ANNOUNCED_LOOKUP.match?(text)
  end

  # Every way out of the loop comes through here — the ordinary return, the
  # budget ceiling and the iteration ceiling — because each of the three has
  # produced an unkept promise in production at least once. Forcing the call
  # (above) is the fix; this is what happens when forcing did not work, which in
  # practice means the forced call itself errored and fell back to the draft.
  def finish(response)
    response = sanitize(response)
    return response unless ANNOUNCED_LOOKUP.match?(response[:content].to_s)

    raise PromiseUnfulfilled,
          "reply promised a lookup it will never make conv=#{@conversation&.display_id} assistant=#{@assistant.id}"
  end

  # Last line of defence. If even the forced call comes back with markup in it,
  # the customer still must not see it: strip the block and let whatever prose
  # surrounds it stand.
  def sanitize(response)
    text = response[:content].to_s
    return response unless WRITTEN_TOOL_CALL.match?(text)

    log_written_tool_call
    cleaned = text.gsub(%r{<\s*(tool_uses?|function_calls?)\b[^>]*>.*?<\s*/\s*\1\s*>}mi, '')
                  .gsub(/<[^>]{0,80}>/, '').squeeze(' ').strip
    response.merge(content: cleaned)
  end

  def log_written_tool_call
    Rails.logger.warn(
      '[Athenas agent] model wrote a tool call as text; stripping it ' \
      "conv=#{@conversation&.display_id} assistant=#{@assistant.id}"
    )
  end

  # `tool_choice: any` makes the call non-optional — Claude cannot answer with
  # text this time, so the promise it just made becomes the lookup it described.
  # The messages are unchanged (the discarded draft was never appended), so this
  # is the same turn asked again under a constraint, not a new one.
  #
  # Falls back to the original draft if the forced call fails: a reply that
  # over-promises still beats no reply at all.
  def force_tool_use(draft)
    log_forced_tool_use
    claude.chat(
      messages: @messages, system: @system, conversation: @conversation,
      phase: @phase, tools: @tools, tool_choice: { type: 'any' },
      log_context: @log_context, cache_messages: true
    )
  rescue Ai::ClaudeService::Error => e
    Rails.logger.warn("[Athenas agent] forced tool call failed conv=#{@conversation&.display_id}: #{e.message}")
    draft
  end

  def log_forced_tool_use
    Rails.logger.info(
      '[Athenas agent] reply announced a lookup with no tool call, forcing one ' \
      "conv=#{@conversation&.display_id} assistant=#{@assistant.id}"
    )
  end

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
