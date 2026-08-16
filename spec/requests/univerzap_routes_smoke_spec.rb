# frozen_string_literal: true

require 'rails_helper'

# Todas as rotas GET que este projeto acrescentou ao fork, abertas uma vez cada,
# por um administrador, só para provar que nenhuma explode ao ser instanciada.
#
# ## O bug que este arquivo existe para pegar
#
# O `check_authorization` herdado deriva o model pelo nome do controller:
# "reports" vira `Report`. Não existe classe `Report` nesta base, então TODA
# requisição para o painel de IA morria com NameError antes de consultar a
# permissão de ninguém. Nenhum spec pegou, porque o spec daquele painel nasceu
# junto com a correção e nenhum outro exercitava a rota.
#
# É uma classe de bug que só aparece quando a rota é de fato aberta: não é erro
# de sintaxe nem de lógica, é uma cadeia de before_action levantando exceção.
# Um spec por controller pega, desde que alguém lembre de escrever. Este
# arquivo tira o "desde que alguém lembre" da equação, porque percorre a tabela
# de rotas em vez de uma lista mantida à mão.
#
# ## Por que só GET
#
# POST e DELETE mudam estado e precisam de corpo válido para significar alguma
# coisa. O que se checa aqui é a montagem do controller e a cadeia de filtros,
# e o GET já exercita isso inteiro.
RSpec.describe 'UniverZAP routes smoke', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  # Prefixos de controller que são nossos. Rota do Chatwoot fica de fora: se
  # ela quebrar, quebrou upstream, e não é aqui que a gente descobre.
  let(:owned_controllers) do
    %w[
      api/v1/accounts/ai/
      api/v1/accounts/whatsapp/
      api/v1/accounts/chatflow
      api/v1/accounts/funnel
      api/v1/accounts/broadcasts
      api/v1/accounts/kanban
    ]
  end

  # Um id que garantidamente não existe. 404 é resposta correta e prova o que
  # interessa: a requisição atravessou o controller inteiro.
  let(:missing_id) { '2147483000' }

  let(:owned_get_routes) do
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller].to_s
      next unless owned_controllers.any? { |prefix| controller.start_with?(prefix) }
      next unless route.verb.to_s.include?('GET')

      route.path.spec.to_s.delete_suffix('(.:format)')
    end.uniq
  end

  def resolve(pattern)
    pattern.gsub(':account_id', account.id.to_s).gsub(/:[a-z_]+/, missing_id)
  end

  # Três recusas que são a resposta CERTA e não falha: id inventado que não
  # existe, rota que exige parâmetro que a varredura não tem como adivinhar, e
  # caminho que nem casa. Nos três casos a requisição atravessou o controller
  # inteiro, que é justamente o que se quer provar. Qualquer outra exceção é o
  # bug que este arquivo procura.
  def failure_for(pattern, headers)
    get resolve(pattern), headers: headers
    nil
  rescue ActiveRecord::RecordNotFound, ActionController::RoutingError, ActionController::ParameterMissing
    nil
  rescue StandardError => e
    "  #{pattern} -> #{e.class}: #{e.message.to_s.truncate(120)}"
  end

  it 'tem rotas nossas para conferir' do
    # Se este número zerar, alguém mexeu nos prefixos e o arquivo virou uma
    # suíte que aprova sem ter testado nada.
    expect(owned_get_routes.length).to be > 5
  end

  it 'nunca levanta excecao ao montar um controller nosso' do
    headers = administrator.create_new_auth_token
    exploded = owned_get_routes.filter_map { |pattern| failure_for(pattern, headers) }

    expect(exploded).to be_empty, "Rotas que levantaram excecao:\n#{exploded.join("\n")}"
  end
end
