# Perfil do número conectado na WAHA: ler, trocar nome, trocar recado e trocar
# ou remover a foto. Todos os endpoints daqui são do WAHA Core e valem nos
# quatro engines (WEBJS, WPP, NOWEB, GOWS).
# Docs: https://waha.devlike.pro/docs/how-to/profile/
#
# Mora num módulo à parte porque WahaSessionService já está perto do teto de
# ClassLength do RuboCop. O cliente HTTP continua sendo um só: estes métodos
# chamam o mesmo `request`, com os mesmos headers e o mesmo tratamento de erro.
module Whatsapp::WahaProfileApi
  def profile
    request(:get, "/api/#{@session_name}/profile")
  end

  def update_profile_name(name)
    request(:put, "/api/#{@session_name}/profile/name", body: { name: name })
  end

  # A WAHA chama de `status` o campo que o WhatsApp mostra como "recado".
  # O nome daqui segue o WhatsApp para não confundir com o status da sessão
  # nem com o status/story, que é outra coisa neste mesmo módulo de tela.
  def update_profile_about(about)
    request(:put, "/api/#{@session_name}/profile/status", body: { status: about })
  end

  # A WAHA baixa a imagem da URL informada, então ela precisa ser alcançável
  # a partir do container da WAHA, e não do navegador do usuário.
  def update_profile_picture(url:)
    request(:put, "/api/#{@session_name}/profile/picture", body: { file: { url: url } })
  end

  def delete_profile_picture
    request(:delete, "/api/#{@session_name}/profile/picture")
  end
end
