# A WAHA entrega com atraso quando o UniverZAP ficou fora ou quando o histórico é
# importado (`messages pull`), e avisa com um carimbo no fim do texto:
#   `🗓️ sex., 30 de out. • 19:37 UTC`
# Sem tratamento a mensagem nasceria com a hora da entrega, pularia para o topo
# da fila, reabriria conversa encerrada e ainda acionaria robô e saudação para o
# cliente. Aqui ela nasce com a hora real; acima de uma hora de atraso entra em
# silêncio, porque é histórico e não conversa em andamento.
module WahaDelayedDelivery
  extend ActiveSupport::Concern

  STAMP = /\s*`[^`\n]*?(\d{1,2}) de ([a-z]+)\.? \S+ (\d{2}):(\d{2}) UTC`\s*\z/
  MONTHS = %w[jan fev mar abr mai jun jul ago set out nov dez].freeze
  MINIMUM_DELAY = 2.minutes
  LIVE_WINDOW = 1.hour

  included do
    before_create :apply_waha_delivery_time
  end

  def delayed_delivery?
    content_attributes['delayed_delivery'].present?
  end

  def historical_delivery?
    delayed_delivery? && created_at < LIVE_WINDOW.ago
  end

  private

  def apply_waha_delivery_time
    match = content.to_s.match(STAMP)
    return unless match && inbox&.channel.try(:waha_bridge?)

    sent_at = stamp_time(match)
    return if sent_at.nil? || sent_at > MINIMUM_DELAY.ago

    self.created_at = sent_at
    self.content = content.sub(STAMP, '')
    self.processed_message_content = content
    self.content_attributes = content_attributes.merge('delayed_delivery' => true)
  end

  def stamp_time(match)
    month = MONTHS.index(match[2][0, 3])
    return if month.nil?

    time = Time.utc(Time.current.year, month + 1, match[1].to_i, match[3].to_i, match[4].to_i)
    time > Time.current ? time - 1.year : time
  rescue ArgumentError
    nil
  end

  # Mensagem atrasada que já tem outra mais nova na conversa não pode mudar quem
  # teve a última palavra nem a hora da última atividade.
  def superseded_delivery?
    return false unless delayed_delivery?

    conversation.messages.where.not(message_type: :activity).where.not(id: id).exists?(['messages.created_at > ?', created_at])
  end

  # Etiqueta e atribuição automáticas de uma conversa histórica não são atividade
  # nova: sem isso a conversa voltaria para "agora" logo depois de importada.
  def activity_after_delayed_delivery?
    activity? && conversation.messages.non_activity_messages.first&.delayed_delivery?
  end

  def backdate_conversation
    return unless delayed_delivery? && created_at < conversation.created_at

    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_columns(created_at: created_at)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def record_historical_delivery
    return if superseded_delivery?

    if valid_first_reply?
      conversation.update(first_reply_created_at: created_at, waiting_since: nil)
    else
      update_waiting_since
    end
  end
end
