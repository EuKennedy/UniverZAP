# The only guardrail the agent cannot evaluate about itself.
#
# Every other flag is computed from the reply. This one comes from the customer's
# NEXT message: a person writing "não é isso" or "tá errado" is telling us the
# previous answer was wrong, and that judgement beats any self-assessment the
# model can produce. It is deterministic on purpose (a regex, no model call), so
# it costs nothing to run on every inbound message.
module Ai::Guardrails::CustomerSignal
  module_function

  # Asking for a person is the single strongest signal the module gets, so the
  # article matters: "quero falar com A atendente" is the most natural phrasing
  # in Brazilian Portuguese and used to slip through a pattern that only allowed
  # "um/uma".
  HUMAN_REQUEST_SOURCE = '
    (?:falar|atendimento|conversar)\s+com\s+(?:(?:um|uma|o|a)\s+)?(?:humano|atendente|pessoa|gente)|
    quero\s+(?:(?:um|uma|o|a)\s+)?(?:humano|atendente)|
    (?:me\s+)?(?:passa|transfere|chama)\s+(?:pra|para\s+)?(?:um[ao]?\s+)?(?:humano|atendente|pessoa)
  '.freeze

  # Deliberately conservative. A false positive puts a good reply in the review
  # queue, which wastes an operator's minute; being too loose would fill the
  # queue with normal conversation and the queue would stop being read at all.
  #
  # Bare adjectives ("péssimo", "horrível") are NOT here. In the beauty vertical
  # they are overwhelmingly the customer describing their own problem ("meu
  # cabelo tá péssimo depois da progressiva"), which is the opposite of a
  # complaint about the agent.
  DISSATISFACTION = /
    n[ãa]o\s+(?:[ée]|era|foi)\s+(?:isso|bem\s+assim|o\s+que)|
    n[ãa]o\s+(?:entendeu|pedi|perguntei|foi\s+isso|[ée]\s+isso)|
    (?:t[áa]|est[áa])\s+errad|
    voc[êe]\s+(?:errou|se\s+enganou|entendeu\s+errado)|
    nada\s+a\s+ver|
    n[ãa]o\s+gostei\s+d(?:o|a|esse|essa|isso)|
    #{HUMAN_REQUEST_SOURCE}
  /xi

  def dissatisfied?(text)
    text.to_s.match?(DISSATISFACTION)
  end
end
