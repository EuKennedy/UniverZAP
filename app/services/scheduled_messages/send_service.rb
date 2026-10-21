# Envia UMA mensagem agendada que o scanner já reservou (status `sending`).
#
# Mesmo caminho do disparo e do Chatflow: Messages::MessageBuilder, então a
# mensagem aparece na conversa e sai pela conexão WAHA da inbox. Nunca levanta:
# um erro vira `failed` com o motivo, para o atendente ver no indicador.
class ScheduledMessages::SendService
  # Quando a janela fecha no meio, a próxima abertura recebe um pequeno
  # espalhamento para dez lembretes não saírem todos às 9h00 em ponto.
  WINDOW_JITTER = 0..900

  def initialize(scheduled_message)
    @scheduled = scheduled_message
  end

  def perform
    return unless @scheduled.status_sending?
    return @scheduled.cancel!('opted_out') if Broadcasts::RecipientGuard.opted_out?(@scheduled.contact)
    return postpone if @scheduled.respect_window && !window.open?

    message = Messages::MessageBuilder.new(@scheduled.created_by, @scheduled.conversation,
                                           { content: rendered_content, message_type: 'outgoing' }).perform
    @scheduled.update!(status: :sent, sent_at: Time.current, message_id: message.id, error: nil)
  rescue StandardError => e
    Rails.logger.error("[Scheduled message] id=#{@scheduled.id} #{e.message}")
    @scheduled.update!(status: :failed, error: e.message.truncate(250))
  end

  private

  def rendered_content
    Broadcasts::MessageRenderer.new(contact: @scheduled.contact, conversation: @scheduled.conversation, seed: @scheduled.id)
                               .render(@scheduled.content)
  end

  def postpone
    @scheduled.update!(status: :scheduled, send_at: window.next_open + rand(WINDOW_JITTER).seconds)
  end

  def window
    @window ||= Broadcasts::SendWindow.default_for(@scheduled.account)
  end
end
