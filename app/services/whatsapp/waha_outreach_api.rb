# As duas travas do WhatsApp para mensagem a contato novo, lidas na hora pela
# WAHA (https://waha.devlike.pro/docs/how-to/sessions/#reachout-timelock):
# a Reachout Timelock (envio falha com erro 463 até `timeEnforcementEnds`) e o
# Message Capping (erro 475 até `cycleEnd`, o fim do ciclo da cota). As duas
# deixam a sessão WORKING e nenhuma sai com restart: quem decide quando parar
# de prospectar é Whatsapp::WahaOutreachGuard.
module Whatsapp::WahaOutreachApi
  def timelock
    request(:get, "/api/sessions/#{@session_name}/timelock")
  end

  def capping
    request(:get, "/api/sessions/#{@session_name}/capping")
  end
end
