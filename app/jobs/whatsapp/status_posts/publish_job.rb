# Publica um status já marcado como `publishing`. Sem retry do Sidekiq: ver
# Whatsapp::StatusPosts::Publisher sobre por que repetir sozinho é perigoso.
class Whatsapp::StatusPosts::PublishJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false

  def perform(post_id)
    post = WhatsappStatusPost.find_by(id: post_id)
    return unless post&.status_publishing?

    Whatsapp::StatusPosts::Publisher.new(post).perform
  rescue StandardError
    # Um erro inesperado não pode deixar o post preso em "publicando" para
    # sempre: o que não saiu vira falha visível, com reenvio na tela.
    abandon!(post)
    raise
  end

  private

  def abandon!(post)
    return if post.blank?

    post.deliveries.status_pending.find_each do |delivery|
      delivery.update!(status: :failed, error_message: I18n.t('inbox.whatsapp.waha.status_unexpected_error'))
    end
    post.refresh_outcome!
  end
end
