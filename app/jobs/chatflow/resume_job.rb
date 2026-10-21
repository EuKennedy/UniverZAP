# Solta uma execução parada numa etapa de relógio ("Digitando…" curto). As
# esperas longas são soltas pelo scanner minuto a minuto; os dois caminhos
# passam pela mesma trava (`claim_timer!`), então rodar duas vezes não repete.
class Chatflow::ResumeJob < ApplicationJob
  queue_as :default

  def perform(execution_id)
    execution = ChatflowExecution.find_by(id: execution_id)
    return if execution.nil? || execution.resume_at.nil? || execution.resume_at > 1.second.from_now

    Chatflow::EngineService.resume(execution)
  end
end
