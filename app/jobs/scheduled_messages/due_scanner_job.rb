# Solta as mensagens agendadas cuja hora chegou. Mesmo molde do scanner de
# status do WhatsApp: cron minuto a minuto em vez de um job por mensagem com
# `wait_until`, para editar ou cancelar ser só um update na linha.
class ScheduledMessages::DueScannerJob < ApplicationJob
  queue_as :scheduled_jobs

  # Reservada e nunca concluída (job perdido num restart do Redis/Sidekiq):
  # vira falha visível no indicador. Não reenvia — a primeira tentativa pode
  # ter chegado à cliente e só a confirmação se perdido.
  STUCK_AFTER = 15.minutes

  def perform
    ScheduledMessage.status_sending.where(updated_at: ...STUCK_AFTER.ago).find_each do |scheduled|
      scheduled.update!(status: :failed, error: I18n.t('scheduled_messages.errors.interrupted'))
    end

    ScheduledMessage.due.find_each do |scheduled|
      # O update condicional é a trava: dois scanners sobrepostos não enviam a
      # mesma mensagem duas vezes, porque só um consegue tirar ela de `scheduled`.
      claimed = ScheduledMessage.where(id: scheduled.id, status: :scheduled)
                                .update_all(status: ScheduledMessage.statuses[:sending], updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      ScheduledMessages::SendJob.perform_later(scheduled.id) if claimed == 1
    end

    # O mesmo relógio solta as Esperas do Chatflow e, uma vez por hora, os
    # gatilhos por data — em vez de um segundo cron com outra trava.
    Chatflow::WaitScanner.new.perform
    Chatflow::DateTriggerScanner.new.perform
  end
end
