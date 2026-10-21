# Solta as execuções cuja Espera venceu. Roda dentro do
# ScheduledMessages::DueScannerJob (o mesmo cron minuto a minuto das mensagens
# agendadas), em vez de um agendador próprio: editar ou cancelar uma espera é
# só um update na linha, sem job antigo esquecido no Redis.
class Chatflow::WaitScanner
  BATCH = 200

  def perform
    ChatflowExecution.due.order(:resume_at).limit(BATCH).pluck(:id).each do |id|
      Chatflow::ResumeJob.perform_later(id)
    end
  end
end
