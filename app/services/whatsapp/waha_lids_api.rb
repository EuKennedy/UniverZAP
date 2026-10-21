# Mapeamento LID <-> número na WAHA. Endpoints do WAHA Core, nos quatro
# engines (NOWEB precisa do Store ligado).
# Docs: https://waha.devlike.pro/docs/how-to/contacts/#lids
#
# Módulo à parte pelo mesmo motivo de WahaProfileApi: usa o `request` de
# WahaSessionService sem empurrar aquela classe além do ClassLength.
module Whatsapp::WahaLidsApi
  # {"lid" => "123@lid", "pn" => "5511999@c.us"}; "pn" vem nil quando a sessão
  # ainda não viu o número por trás desse LID. Erro HTTP vira nil: quem chama
  # trata "não resolvido" do mesmo jeito.
  def find_phone_by_lid(lid)
    request(:get, "/api/#{@session_name}/lids/#{lid.to_s.delete_suffix('@lid')}")
  rescue Whatsapp::WahaSessionService::WahaError
    nil
  end
end
