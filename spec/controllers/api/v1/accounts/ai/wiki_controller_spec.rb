# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Ai::WikiController', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ai/wiki" }

  def fetch(as_user)
    get url, headers: as_user.create_new_auth_token, as: :json
  end

  # Quem trava no dia a dia é a atendente, e é ela quem não tem a quem perguntar.
  it 'responde para a atendente, e não só para o administrador' do
    fetch(agent)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['name']).to eq(Ai::Wiki::Seeder::NAME)
  end

  it 'cria o Guia na primeira vez que alguém pede ajuda' do
    expect { fetch(agent) }.to change { account.ai_assistants.wiki.count }.from(0).to(1)
  end

  it 'devolve o mesmo Guia na segunda vez' do
    fetch(agent)
    first = response.parsed_body['id']

    fetch(agent)

    expect(response.parsed_body['id']).to eq(first)
  end

  it 'recusa quem não está autenticado' do
    get url, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  # O Guia é por conta, como todo o resto do Athenas. A base responde 401 para
  # conta de que a pessoa não faz parte — mesma convenção dos irmãos deste
  # controller (reports, manager).
  it 'nunca responde por uma conta de que a pessoa não faz parte' do
    stranger = create(:user, account: create(:account), role: :administrator)

    fetch(stranger)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'não semeia o Guia da conta alheia ao ser sondado por quem é de fora' do
    stranger = create(:user, account: create(:account), role: :administrator)

    expect { fetch(stranger) }.not_to(change { account.ai_assistants.wiki.count })
  end
end
