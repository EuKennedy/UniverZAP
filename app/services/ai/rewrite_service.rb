class Ai::RewriteService
  TONE_OPERATIONS = %w[casual professional friendly confident straightforward].freeze
  REWRITE_OPERATIONS = %w[improve fix_spelling_grammar expand shorten rephrase make_friendly make_formal simplify].freeze
  ALLOWED_OPERATIONS = (TONE_OPERATIONS + REWRITE_OPERATIONS).freeze

  def initialize(content:, operation:, assistant: nil, conversation: nil)
    @content = content.to_s
    @operation = operation.to_s
    @assistant = assistant
    @conversation = conversation
  end

  def perform
    raise Ai::ClaudeService::Error, "Unsupported operation: #{@operation}" unless ALLOWED_OPERATIONS.include?(@operation)
    raise Ai::ClaudeService::Error, 'Empty content' if @content.strip.empty?
    raise Ai::ClaudeService::Error, 'No AI assistant configured' if @assistant.nil?

    response = Ai::ClaudeService.new(assistant: @assistant).chat(
      messages: [{ role: 'user', content: @content }],
      system: system_prompt,
      conversation: @conversation,
      phase: "rewrite_#{@operation}"
    )

    if response[:content].to_s.strip.empty?
      Rails.logger.warn(
        "[Athenas] rewrite empty content assistant=#{@assistant.id} " \
        "operation=#{@operation} stop=#{response[:stop_reason]}"
      )
      raise Ai::ClaudeService::Error, 'Assistant returned empty response'
    end

    response
  end

  private

  def system_prompt
    base = 'Você é um(a) editor(a) de texto que reescreve mensagens preservando o significado original.'
    instruction = operation_instruction
    rules = <<~RULES.strip
      Regras:
      - Retorne APENAS o texto reescrito, sem prefixos, aspas ou explicações.
      - Mantenha o idioma original do texto recebido.
      - Não invente informação que não esteja na mensagem original.
      - Não use markdown a menos que o texto original já use.
    RULES
    [base, instruction, rules].join("\n\n")
  end

  def operation_instruction
    {
      'improve' => 'Melhore a clareza, fluidez e gramática do texto sem mudar o tom.',
      'fix_spelling_grammar' => 'Corrija apenas erros de ortografia e gramática. Não altere o estilo nem o conteúdo.',
      'casual' => 'Reescreva em tom casual, próximo e descontraído.',
      'professional' => 'Reescreva em tom profissional e formal.',
      'friendly' => 'Reescreva em tom amigável e acolhedor.',
      'confident' => 'Reescreva em tom confiante e assertivo.',
      'straightforward' => 'Reescreva de forma direta e objetiva, sem rodeios.',
      'expand' => 'Expanda o texto adicionando detalhes relevantes sem fugir do tema.',
      'shorten' => 'Encurte o texto preservando os pontos essenciais.',
      'rephrase' => 'Reescreva o texto com outras palavras mantendo o sentido.',
      'make_friendly' => 'Reescreva em tom amigável e acolhedor.',
      'make_formal' => 'Reescreva em tom formal e profissional.',
      'simplify' => 'Simplifique o texto para ficar mais fácil de entender.'
    }[@operation]
  end
end
