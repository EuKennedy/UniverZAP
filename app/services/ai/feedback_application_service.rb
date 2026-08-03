# Turns a reviewer's correction into something the agent actually uses.
#
# A feedback table that only stores opinions is a survey, not a training loop.
# The value is here: the moment someone says "the price is wrong, it's R$ 189,90",
# the next customer must get R$ 189,90 — not after a weekly retraining, not after
# an engineer redeploys a prompt.
#
# The routing follows the reason, because different mistakes live in different
# places:
#
#   info_incorreta / preco_inventado / nao_entendeu -> a knowledge document,
#     retrievable on the very next turn.
#   deveria_transbordar -> an escalation intent, so the same request reaches a
#     human instead of the agent.
#   tom_inadequado -> nothing here. Tone is taught by example, not by rule, and
#     it changes how the agent behaves in every conversation, so it only goes
#     live through a prompt version that was A/B tested first.
class Ai::FeedbackApplicationService
  class NotApplicable < StandardError; end

  # Words too common to identify what the customer was asking about.
  STOPWORDS = %w[
    que para como quando onde voce voces uma dos das com por mais meu minha isso
    tem esta este muito sobre pode quero preciso fazer aqui ainda entao porque
    tambem depois antes agora obrigado obrigada
    qual quais quanto quantos quanta quantas
  ].freeze
  MAX_TRIGGERS = 3
  MIN_TRIGGER_LENGTH = 5
  TITLE_MAX = 120

  def initialize(feedback:)
    @feedback = feedback
    @invocation = feedback.ai_invocation
    @assistant = feedback.ai_assistant
  end

  # Returns the feedback with `applied_at` and the created record set, or raises
  # NotApplicable when this reason is deliberately not applied now.
  def perform
    raise NotApplicable, 'reason is not applied immediately' unless @feedback.immediate?

    case @feedback.reason
    when 'deveria_transbordar' then apply_escalation
    else apply_knowledge
    end
    @feedback
  end

  private

  # A question/answer pair, stored as an ordinary knowledge document so it goes
  # through the exact same retrieval the rest of the base does. Anything else
  # would create a second, subtly different source of truth.
  def apply_knowledge
    training = @assistant.trainings.create!(
      account: @assistant.account,
      title: knowledge_title,
      source_type: 'faq',
      category: knowledge_category,
      content: knowledge_content,
      status: 'ready'
    )
    @feedback.update!(ai_training: training, applied_at: Time.current)
  end

  def knowledge_title
    asked = customer_question.presence || 'Correção do atendimento'
    "Correção: #{asked}".truncate(TITLE_MAX)
  end

  # A price correction belongs with the catalogue, so a later price question
  # ranks it alongside the price table instead of competing with it.
  def knowledge_category
    @feedback.reason == 'preco_inventado' ? 'catalog' : 'faq'
  end

  def knowledge_content
    [
      customer_question.presence && "Pergunta do cliente: #{customer_question}",
      "Resposta correta: #{@feedback.corrected_text}",
      wrong_answer_note
    ].compact.join("\n\n")
  end

  # The rejected answer is included on purpose. Retrieval is lexical, so the
  # wrong wording is often the closest match to how the customer will ask again,
  # and the document that comes back then carries the correction with it.
  def wrong_answer_note
    return nil if @invocation&.ai_response.blank?

    "Nunca responda assim: #{@invocation.ai_response.to_s.truncate(500)}"
  end

  def apply_escalation
    intent = @assistant.intents.create!(
      account: @assistant.account,
      name: "Transbordo: #{customer_question.presence || 'revisão humana'}".truncate(80),
      triggers: escalation_triggers.join(', '),
      action: 'escalate_human',
      action_payload: { 'note' => @feedback.corrected_text.to_s.truncate(500) },
      active: true,
      position: next_intent_position
    )
    @feedback.update!(ai_intent: intent, applied_at: Time.current)
  end

  # Ai::Intent#matches? is substring-based, so whole sentences would almost
  # never fire again. Distinctive words are the granularity that actually
  # catches the same request phrased differently; the reviewer can narrow or
  # widen them afterwards in the intents screen.
  def escalation_triggers
    words = customer_question.to_s.downcase.gsub(/[^\p{Alnum}\s]/u, ' ').split
    picked = words.uniq.reject { |w| w.length < MIN_TRIGGER_LENGTH || STOPWORDS.include?(w) }
                  .first(MAX_TRIGGERS)
    picked.presence || ['falar com atendente']
  end

  def next_intent_position
    (@assistant.intents.maximum(:position) || 0) + 1
  end

  def customer_question
    @customer_question ||= @invocation&.user_message.to_s.strip
  end
end
