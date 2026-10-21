# Sugere textos de status do WhatsApp com o assistente de IA da conta.
#
# Devolve três variações para o operador escolher, no tom pedido. Usa o
# primeiro assistente ativo, como o reescritor do painel faz quando não há
# conversa: status é da empresa, não de um atendimento. Nada é publicado daqui;
# a escolhida só preenche o campo.
class Whatsapp::StatusPosts::SuggestionService
  PHASE = 'status_suggestion'.freeze
  VARIATIONS = 3
  SEPARATOR = '---'.freeze
  TONES = {
    'friendly' => 'próximo e acolhedor',
    'elegant' => 'elegante e sofisticado',
    'fun' => 'divertido e leve, com bom humor',
    'urgent' => 'com senso de urgência (vagas limitadas, só hoje), sem exagero'
  }.freeze

  def initialize(account:, prompt:, current_text: nil, kind: 'text', tone: nil)
    @account = account
    @prompt = prompt.to_s.strip
    @current_text = current_text.to_s.strip
    @kind = kind.to_s
    @tone = TONES.fetch(tone.to_s, TONES['friendly'])
  end

  def perform
    raise Ai::ClaudeService::Error, I18n.t('inbox.whatsapp.waha.suggestion_prompt_required') if @prompt.blank? && @current_text.blank?
    raise Ai::ClaudeService::Error, I18n.t('inbox.whatsapp.waha.suggestion_no_assistant') if assistant.nil?

    response = Ai::ClaudeService.new(assistant: assistant).chat(
      messages: [{ role: 'user', content: user_message }], system: system_prompt, phase: PHASE, max_tokens: 900
    )
    texts = parse(response[:content])
    raise Ai::ClaudeService::Error, I18n.t('inbox.whatsapp.waha.suggestion_empty') if texts.empty?

    texts
  end

  private

  def assistant
    @assistant ||= @account.ai_assistants.active.order(:id).first
  end

  def parse(content)
    content.to_s.split(/^\s*#{SEPARATOR}\s*$/o).map { |text| clean(text) }.compact_blank
           .first(VARIATIONS).map { |text| text.truncate(WhatsappStatusPost::BODY_LIMIT, omission: '') }
  end

  def clean(text)
    text.strip.sub(/\A\d+[.)]\s*/, '').delete_prefix('"').delete_suffix('"').strip
  end

  def user_message
    parts = []
    parts << "Assunto: #{@prompt}" if @prompt.present?
    parts << "Rascunho atual (melhore mantendo a ideia):\n#{@current_text}" if @current_text.present?
    parts.join("\n\n")
  end

  def system_prompt
    <<~PROMPT.strip
      Você escreve status (stories) de WhatsApp para a empresa "#{@account.name}".
      #{@kind == 'text' ? 'O texto é o próprio status, sobre fundo colorido.' : 'O texto é a legenda de uma foto ou vídeo.'}
      Tom: #{@tone}.
      Escreva #{VARIATIONS} variações diferentes entre si, separadas por uma linha contendo apenas #{SEPARATOR}.
      Regras:
      - Retorne APENAS as variações e os separadores, sem numeração, aspas, títulos ou explicações.
      - Cada variação curta e direta: no máximo 3 frases e #{@kind == 'text' ? 250 : 400} caracteres.
      - Português do Brasil, com no máximo 2 emojis por variação.
      - Termine cada uma com uma chamada para ação simples (ex.: "Chama no WhatsApp para agendar").
      - Não invente preços, datas, endereços ou promoções que não estejam no assunto.
      - Sem markdown e sem hashtags.
    PROMPT
  end
end
