# Os números do topo de "Campanhas de disparo": o que saiu, o que vem aí, quanto
# volta como resposta e quanto a proteção segurou. Mais o uso de HOJE de cada
# conexão contra o teto anti-bloqueio — é o número que o dono olha antes de
# disparar mais uma campanha no mesmo WhatsApp.
#
# "Saiu" soma disparos e passos de sequência (os dois são automáticos e contam
# no teto); a mensagem agendada à mão pelo atendente entra em "agendadas".
class Broadcasts::Stats
  def initialize(account, now: Time.current)
    @account = account
    @now = now
    @recipients = BroadcastRecipient.joins(:broadcast).where(broadcasts: { account_id: account.id })
    @scheduled = account.scheduled_messages
  end

  def to_h
    {
      sent_7d: sent_since(7.days.ago(@now)),
      scheduled: @scheduled.status_scheduled.count + @account.broadcasts.status_scheduled.count,
      next_scheduled_at: next_scheduled_at&.iso8601,
      reply_rate_30d: reply_rate,
      skipped_7d: @recipients.status_skipped.where(updated_at: 7.days.ago(@now)..).count,
      opted_out: @account.contacts.where("contacts.custom_attributes->>'#{Broadcasts::RecipientGuard::OPT_OUT_ATTRIBUTE}' = 'true'").count,
      running: @account.broadcasts.status_running.count,
      sequences_enabled: @account.message_sequences.enabled.count,
      connections: connections
    }
  end

  private

  def sent_since(time)
    @recipients.where(sent_at: time..).count + @scheduled.status_sent.where(sent_at: time..).count
  end

  def next_scheduled_at
    [@scheduled.status_scheduled.minimum(:send_at), @account.broadcasts.status_scheduled.minimum(:scheduled_at)].compact.min
  end

  # nil quando nada saiu no período: "0%" diria que ninguém responde.
  def reply_rate
    sent = @recipients.where(sent_at: 30.days.ago(@now)..)
    total = sent.count
    return if total.zero?

    ((sent.where.not(replied_at: nil).count * 100.0) / total).round
  end

  # Uso de hoje (no fuso do salão) e da última hora de cada conexão que já
  # disparou, contra os tetos padrão — os mesmos que o DispatchJob aplica.
  def connections
    day_start = @now.in_time_zone(Broadcasts::SendWindow.default_for(@account).zone).beginning_of_day
    inbox_ids = @account.broadcasts.where.not(inbox_id: nil).distinct.pluck(:inbox_id)
    @account.inboxes.where(id: inbox_ids).order(:name).map do |inbox|
      { inbox_id: inbox.id, name: inbox.name, today: automated_on(inbox, day_start), last_hour: automated_on(inbox, 1.hour.ago(@now)),
        daily_cap: Broadcast::THROTTLE_DEFAULTS['daily_cap'], hourly_cap: Broadcast::THROTTLE_DEFAULTS['hourly_cap'] }
    end
  end

  def automated_on(inbox, since)
    @recipients.where(broadcasts: { inbox_id: inbox.id }).where(sent_at: since..).count +
      @scheduled.status_sent.where(inbox_id: inbox.id).where.not(message_sequence_id: nil).where(sent_at: since..).count
  end
end
