# Uma leitura de conversas, fora da requisição.
#
# Fora dela por necessidade e não por estilo: as verificações do Gerente só leem
# o banco e podem responder no mesmo clique, mas esta chama modelo uma vez por
# conversa e uma varredura de sessenta leva minutos. Segurar a requisição por
# esse tempo entregaria um timeout de proxy no lugar do resultado, e o operador
# concluiria que a feature não funciona.
#
# Fila `:low` pelo mesmo motivo do resto do Athenas fora da conversa: o Sidekiq
# desta base roda em prioridade estrita, e uma leitura de auditoria nunca pode
# disputar worker com o cliente esperando resposta no WhatsApp.
#
# Não relança. O serviço já grava a varredura como `failed` com o motivo, e a
# tela mostra isso com o botão de rodar de novo do lado: repetir sozinho uma
# varredura que chama modelo é a maneira mais rápida de transformar um bug em
# uma fatura.
class Ai::Manager::ConversationScanJob < ApplicationJob
  queue_as :low

  def perform(scan_id)
    scan = Ai::Manager::ConversationScan.find_by(id: scan_id)
    # Só `running`: o segundo clique no botão, ou um retry manual do Sidekiq,
    # não pode reprocessar uma varredura que já terminou e cobrar de novo.
    return if scan.nil? || !scan.running?

    Ai::Manager::Conversations::ScanService.new(scan: scan).perform
  end
end
