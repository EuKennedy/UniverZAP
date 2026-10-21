# Sem retry de propósito: uma nova tentativa automática pode mandar a mesma
# mensagem duas vezes se a primeira chegou e só a resposta se perdeu. A falha
# fica visível no indicador da conversa para o atendente decidir.
class ScheduledMessages::SendJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false

  def perform(scheduled_message_id)
    scheduled = ScheduledMessage.find_by(id: scheduled_message_id)
    ScheduledMessages::SendService.new(scheduled).perform if scheduled
  end
end
