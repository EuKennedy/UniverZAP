# Uma varredura do Gerente sobre uma conta, fora da requisição.
#
# Fila `:low` pelo mesmo motivo que o laboratório A/B: o Sidekiq desta base roda
# 10 threads em prioridade estrita sobre todas as filas, e uma auditoria nunca
# pode disputar worker com o cliente que está esperando resposta no WhatsApp.
#
# Não relança: o serviço já grava a rodada como `failed` com o motivo, e uma
# tentativa automática só repetiria a mesma varredura sobre os mesmos dados. Se
# falhou por bug, o retry falha igual; se falhou por indisponibilidade, a
# próxima semana resolve.
class Ai::Manager::AnalysisJob < ApplicationJob
  queue_as :low

  def perform(account_id, triggered_by = 'schedule', user_id = nil)
    account = Account.find_by(id: account_id)
    return if account.blank?

    Ai::Manager::AnalysisService.new(
      account: account, triggered_by: triggered_by, user: requester(account, user_id)
    ).perform
  end

  private

  # Dentro da conta, e não `User.find_by(id:)` solto. Hoje só o agendador
  # enfileira e o id vem nulo, mas o dia em que a tela passar a disparar a
  # varredura por aqui é o dia em que um id de fora viraria "quem mandou rodar"
  # na auditoria de outra conta. O filtro custa nada e fecha a porta antes.
  def requester(account, user_id)
    return nil if user_id.blank?

    account.users.find_by(id: user_id)
  end
end
