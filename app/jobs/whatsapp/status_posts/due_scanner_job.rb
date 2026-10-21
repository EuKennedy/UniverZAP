# Solta os status agendados cuja hora chegou. Roda a cada minuto pelo cron em
# vez de cada post carregar um job com `wait_until`: reagendar ou cancelar vira
# só um update na linha, sem job velho no Redis disparando na hora antiga.
class Whatsapp::StatusPosts::DueScannerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    WhatsappStatusPost.due.find_each do |post|
      # O update condicional é a trava: dois scanners sobrepostos não publicam
      # o mesmo post duas vezes, porque só um consegue tirar ele de `scheduled`.
      claimed = WhatsappStatusPost.where(id: post.id, status: :scheduled)
                                  .update_all(status: WhatsappStatusPost.statuses[:publishing], updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      next unless claimed == 1

      # A série segue mesmo que esta publicação falhe: a terça que vem não
      # depende de a WAHA ter respondido hoje.
      post.schedule_next_occurrence!
      Whatsapp::StatusPosts::PublishJob.perform_later(post.id)
    end
  end
end
