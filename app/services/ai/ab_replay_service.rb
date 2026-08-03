# Re-asks one real customer question with a candidate prompt version, offline.
#
# Two guarantees this service exists to keep:
#
#   1. Nothing is ever delivered. There is no conversation to reply into, no
#      job, no message builder. A replay that could reach a customer would make
#      the lab unusable on a live account, which is the only account with
#      questions worth replaying.
#   2. Column A is never regenerated. The comparison is against the reply the
#      customer actually received, read from the log.
#
# Retrieval runs fresh rather than reusing the stored chunk list, matching the
# spec: the candidate is judged on the base as it is TODAY, because that is the
# base it would answer from if promoted.
class Ai::AbReplayService
  include Ai::KnowledgeGrounding

  class AlreadyCompared < StandardError; end

  RESPONSE_MAX_CHARS = 60_000

  def initialize(invocation:, version:)
    @invocation = invocation
    @version = version
    @assistant = version.ai_assistant
    # KnowledgeGrounding retrieves against the conversation this reply came
    # from, which is exactly the context that produced the original question.
    @conversation = invocation.conversation_id && Conversation.find_by(id: invocation.conversation_id)
  end

  def perform
    raise AlreadyCompared, 'this reply was already compared to this version' if existing_comparison

    started_at = Time.zone.now
    response = call_candidate
    content, confidence = Ai::MetaBlock.extract(response[:content])
    build_comparison(content, confidence, response, started_at)
  end

  private

  def existing_comparison
    Ai::AbComparison.find_by(ai_invocation_id: @invocation.id, ai_prompt_version_id: @version.id)
  end

  # `max_tokens` is NOT overridden: a duel that capped the candidate at a
  # different length would measure an agent that is not the one that would go
  # live, and length is most of what a reviewer is judging.
  #
  # `phase: 'replay'` keeps lab spend out of the ROI panel, where it would show
  # up as the cost of serving customers. No conversation and no log_context: a
  # replay is a measurement, and writing it into the response log would pollute
  # the supervision queue with answers nobody received.
  def call_candidate
    Ai::ClaudeService.new(assistant: @assistant).chat(
      messages: [{ role: 'user', content: question }],
      system: candidate_prompt,
      phase: 'replay'
    )
  end

  def build_comparison(content, confidence, response, started_at)
    Ai::AbComparison.create!(
      ai_invocation: @invocation, ai_prompt_version: @version,
      ai_assistant: @assistant, account: @assistant.account,
      response_b: content.to_s.truncate(RESPONSE_MAX_CHARS),
      # The candidate is held to the same anti-fabrication bar as production.
      # A single one of these blocks promotion, whatever the win rate says.
      critical_loss: ungrounded_claims(content).any?,
      telemetry_b: telemetry(response, confidence, started_at)
    )
  end

  def telemetry(response, confidence, started_at)
    invocation = response[:invocation]
    {
      'cost_brl' => invocation&.cost_brl.to_f,
      'latency_ms' => ((Time.zone.now - started_at) * 1000).to_i,
      'confidence' => confidence,
      'chunks' => relevant_passages.length,
      'model' => response[:model]
    }
  end

  def question
    @invocation.user_message.presence || 'Oi'
  end

  # The candidate's own instructions, wrapped in the same non-negotiable rules
  # production uses. Judging a candidate without the veracity rule would measure
  # a prompt that will never actually run.
  def candidate_prompt
    [
      "Você é o atendente real falando com o cliente agora. Persona: #{@assistant.name}, #{@assistant.role}.",
      @version.system_prompt.presence,
      few_shot_block,
      knowledge_snippets,
      GROUNDING_RULES,
      Ai::MetaBlock::INSTRUCTION
    ].compact.join("\n\n")
  end

  def few_shot_block
    pairs = @version.few_shot_pairs
    return nil if pairs.empty?

    lines = pairs.map { |pair| "Cliente: #{pair['question']}\nVocê: #{pair['answer']}" }
    "EXEMPLOS DE RESPOSTA IDEAL (imite o tom e o formato, não o conteúdo):\n#{lines.join("\n\n")}"
  end

  # KnowledgeGrounding needs a conversation for history-based grounding. A log
  # row whose conversation was deleted still has its question, so the replay
  # runs with knowledge and prompt as the only sanctioned sources.
  def knowledge_query
    @knowledge_query ||= question
  end

  def latest_user_message
    question
  end

  # The candidate is judged ONLY on what it actually carries: its own
  # instructions, the knowledge base, and the question it was asked. Letting the
  # LIVE prompt count as a source would sanction a candidate quoting a price its
  # own wording never mentions, which is exactly the failure critical_loss
  # exists to catch.
  def grounding_sources
    @grounding_sources ||= [
      relevant_passages.pluck(:body).join(' '),
      @version.system_prompt.to_s,
      @invocation.user_message.to_s
    ].join(' ')
  end
end
