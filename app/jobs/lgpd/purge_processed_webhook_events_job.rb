class Lgpd::PurgeProcessedWebhookEventsJob < ApplicationJob
  queue_as :scheduled_jobs

  # Cron diário: remove dedup-rows de webhooks Univercart com mais de 90
  # dias. O replay window real é de 5 minutos (vide
  # Univercart::Signature), 90 dias é folga absurda mas preserva trilha
  # de auditoria curta antes do purge.
  RETENTION = 90.days

  def perform
    UnivercartProcessedEvent.where('processed_at < ?', RETENTION.ago).delete_all
  end
end
