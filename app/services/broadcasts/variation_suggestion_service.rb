# Pede ao assistente de IA da conta 2–3 versões do mesmo texto, para o
# disparo não mandar a mensagem idêntica a todo mundo (mensagem repetida em
# massa é um dos sinais que derrubam número não oficial).
#
# Mesmo assistente e mesmo cliente do "Meu WhatsApp" (Whatsapp::StatusPosts::
# SuggestionService). O operador revisa antes de salvar: a sugestão só
# preenche os campos de versão.
class Broadcasts::VariationSuggestionService
  PHASE = 'broadcast_variations'.freeze
  COUNT = 3
  SEPARATOR = '---'.freeze

  def initialize(account:, text:)
    @account = account
    @text = text.to_s.strip
  end

  def perform
    raise Ai::ClaudeService::Error, I18n.t('scheduled_messages.variations.text_required') if @text.blank?
    raise Ai::ClaudeService::Error, I18n.t('inbox.whatsapp.waha.suggestion_no_assistant') if assistant.nil?

    response = Ai::ClaudeService.new(assistant: assistant).chat(
      messages: [{ role: 'user', content: @text }], system: system_prompt, phase: PHASE, max_tokens: 900
    )
    variations = parse(response[:content])
    raise Ai::ClaudeService::Error, I18n.t('inbox.whatsapp.waha.suggestion_empty') if variations.empty?

    variations
  end

  private

  def assistant
    @assistant ||= @account.ai_assistants.active.order(:id).first
  end

  def parse(content)
    content.to_s.split(/^\s*#{SEPARATOR}\s*$/o).map { |part| part.strip.delete_prefix('"').delete_suffix('"').strip }
           .compact_blank.reject { |part| part == @text }.first(COUNT)
  end

  def system_prompt
    <<~PROMPT.strip
      Você reescreve mensagens de WhatsApp que a empresa "#{@account.name}" envia para clientes.
      Escreva #{COUNT} versões diferentes da mensagem do usuário, com o MESMO sentido e a mesma chamada para ação.
      Regras:
      - Separe as versões com uma linha contendo apenas #{SEPARATOR}. Nada antes, nada depois.
      - Mude a abertura, a ordem e as palavras; mantenha o tamanho parecido.
      - Mantenha EXATAMENTE as variáveis entre chaves que existirem (ex.: {primeiro_nome}, {servico}).
      - Português do Brasil, tom próximo, no máximo 1 emoji por versão.
      - Não invente preços, datas, descontos ou promessas que não estejam no texto.
      - Sem markdown e sem hashtags.
    PROMPT
  end
end
