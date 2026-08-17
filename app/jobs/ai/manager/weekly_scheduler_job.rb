# A varredura semanal do Gerente, uma rodada por conta.
#
# A lista de contas sai de `ai_assistants`, que tem uma linha por agente, e nunca
# do log de invocações, que é a maior tabela da plataforma: decidir quem auditar
# não pode custar uma varredura do tráfego de todo mundo.
#
# Conta com agente e sem movimento também é enfileirada, de propósito. Quem
# decide que a amostra é pequena demais é Ai::Manager::AnalysisService, que grava
# a recusa como `insufficient_data` e diz quantas conversas faltam. Filtrar aqui
# faria essa conta simplesmente não ter rodada nenhuma, e o operador abriria a
# tela sem saber se o Gerente não achou nada ou nem olhou.
#
# Uma rodada por conta em job separado, e não tudo aqui: uma conta grande e lenta
# não pode segurar a auditoria das outras trezentas atrás dela.
class Ai::Manager::WeeklySchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Ai::Assistant.active.distinct.pluck(:account_id).uniq.each do |account_id|
      Ai::Manager::AnalysisJob.perform_later(account_id, 'schedule')
    end
  end
end
