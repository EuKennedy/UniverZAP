# Publica um WhatsappStatusPost em cada conexão escolhida e registra o que
# aconteceu em cada uma.
#
# Nunca tenta de novo sozinho: um status que a WAHA aceitou mas respondeu tarde
# demais pareceria falha, e repetir publicaria o mesmo story duas vezes para
# todos os contatos. O reenvio é sempre uma decisão do operador, e só alcança
# as entregas que estão `failed`.
class Whatsapp::StatusPosts::Publisher
  # Um timeout não diz se o status saiu ou não. Tratamos como falha, mas a
  # mensagem manda conferir no celular antes de reenviar.
  NETWORK_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError].freeze

  def initialize(post)
    @post = post
    @resolver = Whatsapp::WahaInboxResolver.new(post.account)
  end

  def perform
    ensure_deliveries!
    @post.deliveries.status_pending.find_each { |delivery| deliver(delivery) }
    @post.refresh_outcome!
  end

  private

  def ensure_deliveries!
    @post.with_lock do
      next if @post.deliveries.exists?

      @post.target_inboxes.each do |inbox|
        @post.deliveries.create!(inbox: inbox, inbox_name: inbox.name)
      end
    end
  end

  def deliver(delivery)
    inbox, service = @resolver.resolve!(delivery.inbox_id)
    response = send_to(service, Whatsapp::StatusPosts::Variables.render(@post.body, account: @post.account, inbox_name: inbox.name))
    delivery.update!(status: :sent, sent_at: Time.current, error_message: nil, waha_message_id: message_id(response))
  rescue Whatsapp::WahaSessionService::WahaError => e
    fail!(delivery, Whatsapp::WahaErrorMessage.humanize(e.message))
  rescue Whatsapp::WahaInboxResolver::NotWahaInboxError, ActiveRecord::RecordNotFound
    fail!(delivery, I18n.t('inbox.whatsapp.waha.not_a_waha_inbox'))
  rescue *NETWORK_ERRORS
    fail!(delivery, I18n.t('inbox.whatsapp.waha.status_timeout'))
  end

  def fail!(delivery, message)
    delivery.update!(status: :failed, error_message: message.to_s.truncate(500))
  end

  def send_to(service, body)
    case @post.kind
    when 'text'
      service.send_status_text(text: body, background_color: @post.background_color.presence, font: @post.font)
    when 'image'
      service.send_status_image(url: media_url, caption: body.presence, mimetype: @post.media.blob.content_type)
    when 'video'
      service.send_status_video(url: media_url, caption: body.presence, mimetype: @post.media.blob.content_type,
                                background_color: @post.background_color.presence)
    end
  end

  # A URL é gerada por envio, e não uma vez para o post: num agendamento para
  # daqui a dois dias, uma URL assinada de 15 minutos já teria vencido.
  def media_url
    Whatsapp::WahaMediaUrl.for(@post.media.blob)
  end

  # A WAHA devolve a mensagem criada; o id vem em formatos diferentes por
  # engine (string ou { _serialized }). Guardamos o que vier para suporte.
  def message_id(response)
    return unless response.is_a?(Hash)

    id = response['id'] || response.dig('key', 'id')
    (id.is_a?(Hash) ? id['_serialized'] || id['id'] : id)&.to_s
  end
end
