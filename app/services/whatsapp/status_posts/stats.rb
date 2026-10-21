# Os números do topo de "Meu WhatsApp": o que saiu, o que vem aí e quanto
# está falhando. Tudo vem das entregas, que são o que de fato aconteceu em
# cada número, e não dos posts, que são só a intenção.
class Whatsapp::StatusPosts::Stats
  def initialize(account, now: Time.current)
    @posts = account.whatsapp_status_posts
    @deliveries = WhatsappStatusDelivery.joins(:whatsapp_status_post).where(whatsapp_status_posts: { account_id: account.id })
    @now = now
  end

  def to_h
    next_post = @posts.status_scheduled.where(scheduled_at: @now..).order(:scheduled_at).first
    {
      published_7d: @deliveries.status_sent.where(sent_at: 7.days.ago(@now)..).count,
      scheduled: @posts.status_scheduled.count,
      drafts: @posts.status_draft.count,
      failed_7d: @deliveries.status_failed.where(updated_at: 7.days.ago(@now)..).count,
      success_rate_30d: success_rate,
      next_scheduled_at: next_post&.scheduled_at&.iso8601
    }
  end

  private

  # nil quando nada terminou no período: "0%" diria que tudo falhou.
  def success_rate
    finished = @deliveries.where.not(status: :pending).where(updated_at: 30.days.ago(@now)..)
    total = finished.count
    return if total.zero?

    ((finished.status_sent.count * 100.0) / total).round
  end
end
