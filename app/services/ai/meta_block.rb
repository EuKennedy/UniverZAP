# Claude is asked to close every customer-facing reply with a machine-readable
# self-assessment:
#
#   <meta>{"confidence":0.94}</meta>
#
# It costs about ten tokens and turns "is this answer safe to send unreviewed?"
# into a number the supervision queue can sort on. The block is internal, so it
# is stripped here before the text can reach anybody.
#
# Stripping is deliberately forgiving: a model that emits `<meta>` twice, wraps
# it in a code fence, or writes malformed JSON must never leak the tag to a
# customer. Anything that looks like the tag is removed; only well-formed JSON
# yields a confidence.
module Ai::MetaBlock
  module_function

  # Matches the tag anywhere, with or without a surrounding fence, greedy on
  # whitespace so removing it does not leave a dangling blank line. Spaces
  # inside the angle brackets are tolerated: a model that writes `< meta >`
  # would otherwise have its JSON survive the strip and land on WhatsApp.
  PATTERN = %r{\s*(?:```[a-z]*\s*)?<\s*meta\s*>\s*(.*?)\s*<\s*/\s*meta\s*>\s*(?:```)?\s*}mi

  # The instruction appended to the system prompt of every reply-generating
  # path. Phrased as an output-format rule (not a question) because models
  # comply with format directives far more reliably than with requests for
  # introspection.
  INSTRUCTION = <<~META.strip.freeze
    📊 FORMATO OBRIGATÓRIO DE SAÍDA (bloco interno, nunca chega ao cliente):
    Depois do texto da resposta, escreva EXATAMENTE uma última linha:
    <meta>{"confidence":0.0}</meta>
    Troque 0.0 pela sua confiança, de 0 a 1, de que TODO dado factual que você
    afirmou (preço, prazo, horário, condição, disponibilidade) está escrito
    LITERALMENTE em algum bloco acima. Se você afirmou algo que não conseguiu
    conferir, use um valor abaixo de 0.7. Nunca comente esse bloco, nunca o
    mencione ao cliente e nunca escreva nada depois dele.
  META

  # A truncated generation can end mid-tag. Whatever follows an unclosed
  # `<meta>` is internal by definition, so it is cut rather than delivered.
  DANGLING = %r{\s*(?:```[a-z]*\s*)?<\s*meta\s*>(?!.*<\s*/\s*meta\s*>).*\z}mi

  # Last-resort scrub. A model that emits a stray `</meta>` with no opening, or
  # `<meta >` with a space, would otherwise put the tag in front of a customer
  # signed with the salon's name. Nothing shaped like this tag is ever
  # legitimate output, so anything left over is removed unconditionally.
  STRAY = %r{\s*<\s*/?\s*meta\s*>\s*}i
  # Cheap "is there anything tag-shaped at all?" guard, so the common case (no
  # tag) costs one match instead of three.
  ANY_TAG = %r{<\s*/?\s*meta}i

  # Returns [clean_text, confidence_or_nil]. The text is returned stripped of
  # every meta tag; confidence comes from the LAST parseable one.
  def extract(text)
    body = text.to_s
    return [body, nil] unless body.match?(ANY_TAG)

    confidence = body.scan(PATTERN).filter_map { |payload| parse_confidence(payload.first) }.last
    [body.gsub(PATTERN, "\n").sub(DANGLING, '').gsub(STRAY, ' ').strip, confidence]
  end

  def parse_confidence(payload)
    value = JSON.parse(payload.to_s)['confidence']
    return nil unless value.is_a?(Numeric)

    value.to_f.clamp(0.0, 1.0)
  rescue JSON::ParserError
    nil
  end
end
