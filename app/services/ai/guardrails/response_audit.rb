# Automatic review flags computed over a reply just before it is sent.
#
# These do NOT block the reply. Blocking would trade a slightly wrong answer for
# no answer at all, and on WhatsApp silence costs the sale. They mark the log row
# so the supervision queue can put a human on the replies that need one, in
# severity order.
#
# The one hard block in the system stays where it was: a money value that exists
# in no sanctioned source is regenerated and, if it survives, suppressed
# (Ai::AutopilotReplyService#enforce_grounding). This class records that it
# happened; it does not decide it.
class Ai::Guardrails::ResponseAudit
  # Below this, Claude itself is telling us it could not verify what it wrote.
  CONFIDENCE_FLOOR = 0.7

  # The customer is asking for a fact, so answering with an empty knowledge
  # retrieval is worth a look even when the wording sounds confident.
  FACTUAL_QUESTION = /
    \?|
    \b(?:qual|quais|quanto|quantos|quando|onde|tem|t[êe]m|possui|aceita|faz|fazem|
    atende|atendem|dispon[íi]vel|hor[áa]rio|pre[çc]o|valor|custa|prazo|entrega|
    garantia|parcel|frete)\b
  /xi

  # A commitment the agent can only honour if something was actually written to
  # an external system (agenda, order). Two things are deliberately absent:
  # "te mando o link" (sending a link is within the agent's own power) and
  # "posso agendar pra você?" (an offer is not a promise, and treating every
  # offer as one would flag half of a healthy sales conversation).
  LOOSE_PROMISE = /
    \b(?:agendei|reservei|marquei|separei|confirmei|garanti|bloqueei)\b|
    \b(?:vou|j[áa]\s+vou)\s+(?:agendar|reservar|marcar|separar|bloquear)\b|
    \bfica\s+(?:reservad|agendad|marcad|separad)|
    \bdeixei\s+(?:reservad|agendad|marcad|separad)
  /xi

  # Words that turn a weekday mention into a claim about being open.
  AVAILABILITY_CLAIM = /atend|abert|abrimos|abre|funciona|dispon[íi]v|agenda|hor[áa]rio|pode\s+vir|te\s+espero|marcar/i

  # ... unless the sentence is DENYING availability, which is the correct answer.
  #
  # Scoped to the verb, not the whole sentence. A blanket "does it contain não?"
  # made "Não se preocupe, atendemos domingo sim!" look like a denial, so the
  # exact mistake this guardrail exists to catch was the one it let through.
  DENIAL = /
    \bn[ãa]o\s+(?:\w+\s+){0,2}(?:atend|abr|funciona|trabalha|opera)|
    \bfech(?:a|o)|sem\s+atendimento|indispon[íi]v|\bfolga
  /xi

  WEEKDAYS = {
    0 => /\bdomingos?\b/i,
    1 => /\bsegundas?(?:[-\s]+feiras?)?\b/i,
    2 => /\bter[çc]as?(?:[-\s]+feiras?)?\b/i,
    3 => /\bquartas?(?:[-\s]+feiras?)?\b/i,
    4 => /\bquintas?(?:[-\s]+feiras?)?\b/i,
    5 => /\bsextas?(?:[-\s]+feiras?)?\b/i,
    6 => /\bs[áa]bados?\b/i
  }.freeze

  # "Atendemos de segunda a sexta" is how most agents state their hours, and a
  # check that only looked for a literal day name would miss every conflict
  # inside a range: the common phrasing would be the blind spot.
  DAY_INDEX = {
    'domingo' => 0, 'segunda' => 1, 'terça' => 2, 'terca' => 2, 'quarta' => 3,
    'quinta' => 4, 'sexta' => 5, 'sábado' => 6, 'sabado' => 6
  }.freeze
  DAY_ALTERNATION = DAY_INDEX.keys.join('|').freeze
  RANGE = /
    \b(?:de\s+)?(#{DAY_ALTERNATION})s?(?:[-\s]*feiras?)?\s+
    (?:a|at[ée]|à)\s+(#{DAY_ALTERNATION})s?(?:[-\s]*feiras?)?
  /xi

  # Every argument is a distinct input to a distinct guardrail; folding them into
  # an options hash would hide which check reads what.
  def initialize(conversation:, reply:, user_message: nil, chunks: [], confidence: nil, # rubocop:disable Metrics/ParameterLists
                 ungrounded: false, performed_write: false, knowledge_available: true)
    @conversation = conversation
    @reply = reply.to_s
    @user_message = user_message.to_s
    @chunks = Array(chunks)
    @confidence = confidence
    @ungrounded = ungrounded
    @performed_write = performed_write
    @knowledge_available = knowledge_available
  end

  # Every flag that applies, in Ai::Invocation::AUTO_FLAGS severity order.
  def perform
    flags = []
    flags << 'preco_inventado' if @ungrounded
    flags << 'horario_divergente' if schedule_conflict?
    flags << 'promessa_solta' if loose_promise?
    flags << 'sem_fonte' if unsourced_factual_answer?
    flags << 'baixa_confianca' if low_confidence?
    flags
  rescue StandardError => e
    # An audit is never worth losing a reply over.
    Rails.logger.warn("[Athenas guardrails] audit failed conv=#{@conversation&.id}: #{e.message}")
    flags || []
  end

  private

  def low_confidence?
    @confidence.present? && @confidence < CONFIDENCE_FLOOR
  end

  # Only meaningful for an agent that HAS a knowledge base: "your base does not
  # cover this question" is actionable. An agent with no base at all would flag
  # every single reply, and a queue that is 100% one message stops being read.
  # That case belongs in onboarding, not here.
  def unsourced_factual_answer?
    @knowledge_available && @chunks.empty? && @user_message.match?(FACTUAL_QUESTION)
  end

  def loose_promise?
    return false if @performed_write

    @reply.match?(LOOSE_PROMISE)
  end

  # The reply claims the business is available on a day the inbox is marked
  # closed all day. Only runs when the operator actually configured working
  # hours, and only on sentences that are not denying availability.
  def schedule_conflict?
    days = closed_days
    return false if days.empty?

    sentences(@reply).any? { |sentence| open_claim_on_closed_day?(sentence, days) }
  end

  def open_claim_on_closed_day?(sentence, days)
    return false unless sentence.match?(AVAILABILITY_CLAIM)
    return false if sentence.match?(DENIAL)

    claimed = claimed_days(sentence)
    days.any? { |day| claimed.include?(day) }
  end

  # Days the sentence says the business is available, counting both explicit
  # names and ranges ("de segunda a sexta" covers 1..5).
  def claimed_days(sentence)
    named = WEEKDAYS.select { |_day, pattern| sentence.match?(pattern) }.keys
    named + sentence.scan(RANGE).flat_map { |from, to| expand_range(from, to) }
  end

  def expand_range(from, to)
    first = DAY_INDEX[from.to_s.downcase]
    last = DAY_INDEX[to.to_s.downcase]
    return [] if first.nil? || last.nil?

    # "de sexta a segunda" wraps around the week.
    first <= last ? (first..last).to_a : ((first..6).to_a + (0..last).to_a)
  end

  def sentences(text)
    text.split(/(?<=[.!?\n])\s*/).reject(&:blank?)
  end

  def closed_days
    inbox = @conversation&.inbox
    return [] unless inbox&.working_hours_enabled?

    inbox.working_hours.select(&:closed_all_day?).map(&:day_of_week)
  end
end
