# O Guia da conta, criado na primeira vez que alguém pede ajuda.
#
# Existe porque o Guia é deliberadamente invisível na listagem de agentes — a
# operação não gerencia ele — e mesmo assim o widget precisa de um id para abrir
# a thread. Semear aqui em vez de no nascimento da conta evita 18 documentos
# gravados em toda conta criada por um agente que a maioria abre dias depois.
class Api::V1::Accounts::Ai::WikiController < Api::V1::Accounts::BaseController
  def show
    assistant = Ai::Wiki::Seeder.for(Current.account)
    render json: { id: assistant.id, name: assistant.name }
  end
end
