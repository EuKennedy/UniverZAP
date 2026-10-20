# Sugere o texto de um status do WhatsApp com o assistente de IA da conta.
#
# Usa o primeiro assistente ativo, como o reescritor do painel faz quando não
# há conversa: status é da empresa, não de um atendimento. O operador sempre
# revisa antes de publicar, então a sugestão só preenche o campo.
class Whatsapp::StatusPosts::SuggestionService
  PHASE = 'status_suggestion'.freeze

  def initialize(account:, prompt:, current_text: nil, kind: 'text')
    @account = account
    @prompt = prompt.to_s.strip
    @current_text = current_text.to_s.strip
    @kind = kind.to_s
  end

  def perform
    raise Ai::ClaudeService::Error, I18n.t('inbox.whatsapp.waha.suggestion_prompt_required') if @prompt.blank? && @current_text.blank?
    raise Ai::ClaudeService::Error, I18n.t('inbox.whatsapp.waha.suggestion_no_assistant') if assistant.nil?

    response = Ai::ClaudeService.new(assistant: assistant).chat(
      messages: [{ role: 'user', content: user_message }], system: system_prompt, phase: PHASE, max_tokens: 400
    )
    text = response[:content].to_s.strip.delete_prefix('"').delete_suffix('"').strip
    raise Ai::ClaudeService::Error, I18n.t('inbox.whatsapp.waha.suggestion_empty') if text.blank?

    text.truncate(WhatsappStatusPost::BODY_LIMIT, omission: '')
  end

  private

  def assistant
    @assistant ||= @account.ai_assistants.active.order(:id).first
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
      Regras:
      - Retorne APENAS o texto do status, sem aspas, prefixos ou explicações.
      - Curto e direto: no máximo 3 frases e #{@kind == 'text' ? 250 : 400} caracteres.
      - Tom próximo, em português do Brasil, com no máximo 2 emojis.
      - Termine com uma chamada para ação simples (ex.: "Chama no WhatsApp para agendar").
      - Não invente preços, datas, endereços ou promoções que não estejam no assunto.
      - Sem markdown e sem hashtags.
    PROMPT
  end
end
