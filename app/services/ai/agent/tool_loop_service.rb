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

  # Raised when the reply CONFIRMS a booking that no tool ever made. The worst
  # thing this module can do: the customer is told they have an appointment,
  # writes it down, and shows up to a salon expecting nobody.
  #
  # Seen in the sandbox: the agent listed real slots from the agenda, the
  # customer picked one, and the answer was "Fechado, Kennedy! Escova marcada
  # pra quarta às 16h45" with nothing in Google Calendar and no row in our
  # index. Two exits from the loop below produce exactly this — the 90s budget
  # and the six-iteration cap both ask for a closing answer with tool_choice
  # `none`, and a model mid-plan closes by describing the call it was about to
  # make.
  class BookingUnperformed < StandardError; end

  # What a tool says when the write really happened. Matched against the tool
  # RESULT rather than trusting performed_write?, which is set before the work
  # on purpose (a timed-out write may still have landed) and so answers
  # "attempted", not "done".
  WRITE_CONFIRMED = /"(?:agendado|remarcado|desmarcado)"\s*:\s*true/i

  # First person, past or present, next to a time or a weekday.
  BOOKING_CLAIM = /
    \b(?:marquei|agendei|reservei|remarquei|desmarquei|cancelei)\b
    |\b(?:est[áa]|ficou|fica|deixei)\s+(?:tudo\s+)?(?:marcad|agendad|reservad)\w*
    |\b(?:marcad|agendad|reservad)\w*\s+(?:pra|para|em|no|na)\s+
      (?:\d{1,2}\s*[:h]|segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo|hoje|amanh[ãa])
  /xi

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
    @tool_calls = []
  end

  # Readable after #perform, so the caller can show or log what ran.
  attr_reader :tool_calls

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
  # Only a reply that is NOTHING BUT the promise. "Perfeito, deixa eu buscar
  # aqui pra você!" is 38 characters and answers nothing; "Fechado! Já te mando
  # o link do carrinho: https://..." contains the same trigger words and is a
  # complete answer with the link already in it.
  #
  # The first version of this guard checked only the words, so it silenced every
  # reply that closed with "já te mando o link" — which for a sales agent is
  # most of them. Forcing the tool call (above) stays broad because forcing is
  # cheap and recoverable; going silent is neither.
  PROMISE_ONLY_MAX_CHARS = 140
  # What the promise was FOR. A reply carrying a link or a price already
  # delivered whatever it announced, whatever words it wrapped that in.
  DELIVERED = %r{https?://|R\$\s?\d|\d+[.,]\d{2}}i

  def finish(response)
    response = sanitize(response)
    text = response[:content].to_s.strip
    raise_unbooked!(text) if claims_booking?(text) && !@confirmed_write
    return response unless bare_promise?(text)

    raise PromiseUnfulfilled,
          "reply promised a lookup it will never make conv=#{@conversation&.display_id} assistant=#{@assistant.id}"
  end

  def raise_unbooked!(text)
    raise BookingUnperformed,
          'reply confirmed a booking no tool performed ' \
          "conv=#{@conversation&.display_id} assistant=#{@assistant.id} text=#{text.truncate(120).inspect}"
  end

  # Only a claim in the FIRST person about a slot: "marquei", "está agendado
  # para as 14h". Deliberately requires a time or a weekday next to it, so
  # "posso marcar quinta?" and "quer que eu marque?" — questions, which is most
  # of what the agent says while arranging — do not trip it.
  def claims_booking?(text)
    BOOKING_CLAIM.match?(text)
  end

  # All three have to hold before a turn is thrown away: it announces a lookup,
  # it delivered nothing, and it is short enough to be nothing else. Going
  # silent is unrecoverable, so the bar to do it is deliberately high.
  def bare_promise?(text)
    ANNOUNCED_LOOKUP.match?(text) && !DELIVERED.match?(text) && text.length <= PROMISE_ONLY_MAX_CHARS
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
    result = @executor.call(tool_use['name'], tool_use['input'])
    @confirmed_write = true if WRITE_CONFIRMED.match?(result.to_s)
    record_call(tool_use, result)
    {
      type: 'tool_result',
      tool_use_id: tool_use['id'],
      content: result
    }
  end

  # What the agent actually DID this turn, for the sandbox to show. Without it,
  # an operator testing a booking agent can only read the prose and take the
  # agent's word for it — which is precisely the word that turned out to be
  # worthless. Truncated because a slot list is long and the point here is
  # which call happened and whether it worked, not the payload.
  def record_call(tool_use, result)
    @tool_calls << {
      name: tool_use['name'],
      input: tool_use['input'],
      result: result.to_s.truncate(300)
    }
  end
end
