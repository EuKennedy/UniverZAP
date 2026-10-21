# Solta as mensagens agendadas cuja hora chegou. Mesmo molde do scanner de
# status do WhatsApp: cron minuto a minuto em vez de um job por mensagem com
# `wait_until`, para editar ou cancelar ser só um update na linha.
class ScheduledMessages::DueScannerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ScheduledMessage.due.find_each do |scheduled|
      # O update condicional é a trava: dois scanners sobrepostos não enviam a
      # mesma mensagem duas vezes, porque só um consegue tirar ela de `scheduled`.
      claimed = ScheduledMessage.where(id: scheduled.id, status: :scheduled)
                                .update_all(status: ScheduledMessage.statuses[:sending], updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      ScheduledMessages::SendJob.perform_later(scheduled.id) if claimed == 1
    end
  end
end
