# Grupos na WAHA: dados do grupo e participantes, para a extração de
# participantes em listas de distribuição (ContactLists::GroupExtractionService).
# Docs: https://waha.devlike.pro/docs/how-to/groups/
#
# Participantes: a v2 (`/participants/v2`) devolve o formato normalizado
# [{id: "5511…@c.us" | "…@lid", role: participant|admin|superadmin|left}];
# a v1 é a crua do engine (no GOWS: {JID, PhoneNumber, LID, IsAdmin,
# IsSuperAdmin, DisplayName}). Tenta a v2 e cai na v1 se ela não existir na
# versão instalada. Quem chama normaliza os dois formatos.
module Whatsapp::WahaGroupsApi
  def group(group_id)
    request(:get, "/api/#{@session_name}/groups/#{escape_chat_id(group_id)}")
  rescue Whatsapp::WahaSessionService::WahaError
    nil
  end

  def group_participants(group_id)
    path = "/api/#{@session_name}/groups/#{escape_chat_id(group_id)}/participants"
    Array(request(:get, "#{path}/v2"))
  rescue Whatsapp::WahaSessionService::WahaError
    Array(request(:get, path))
  end

  # O número da própria sessão ("5531…@c.us"), para não pôr o salão na lista.
  def own_chat_id
    session.to_h.dig('me', 'id')
  end

  private

  # O id do grupo vem do identifier do contato ("1203…@g.us"); só dígitos,
  # hífen, @ e ponto chegam à URL.
  def escape_chat_id(chat_id)
    value = chat_id.to_s
    raise Whatsapp::WahaSessionService::WahaError, 'invalid chat id' unless value.match?(/\A[0-9-]+@[a-z.]+\z/)

    value
  end
end
