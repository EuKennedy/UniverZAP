# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Ai::ReportsController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:ai_assistant, account: account, name: 'Marina') }
  let(:url) { "/api/v1/accounts/#{account.id}/ai/report" }

  def fetch(as_user, params = {})
    get url, params: params, headers: as_user.create_new_auth_token, as: :json
  end

  it 'answers with the account panel' do
    create(:ai_invocation, account: account, ai_assistant: assistant, message_id: 5, conversation_id: 9)

    fetch(administrator)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['totals']['replies']).to eq(1)
  end

  # 'Sofia' is seeded on every account the moment it is created, so the list is
  # never empty and an idle agent still gets a row.
  it 'names every agent of the account, including the idle ones' do
    assistant
    fetch(administrator)

    expect(response.parsed_body['agents'].map { |row| row['name'] }).to eq(%w[Marina Sofia])
  end

  # The same gate as the rest of Relatórios, by design. This section renders
  # inside that screen, and a 403 hole in a page the product just invited
  # somebody into is worse than either answer on its own.
  it 'refuses somebody who may not read reports' do
    fetch(agent)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses somebody who is not signed in' do
    get url, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  # One panel, many tenants, and the numbers are spend and revenue.
  it 'never answers for an account the person is not in' do
    stranger = create(:user, account: create(:account), role: :administrator)

    fetch(stranger)

    expect(response).to have_http_status(:unauthorized)
  end

  describe 'the period' do
    it 'accepts a preset number of days' do
      fetch(administrator, { days: 7 })

      expect(response.parsed_body['period_days']).to eq(7)
    end

    # O par de datas do calendário, em epoch, que é como o resto de Relatórios
    # já fala com o backend.
    it 'accepts a range picked on the calendar' do
      fetch(administrator, { since: 9.days.ago.to_i, until: 3.days.ago.to_i })

      expect(response.parsed_body['period_days']).to eq(7)
    end

    # Uma data digitada errada não pode derrubar o relatório inteiro: cai no
    # padrão e a tela continua respondendo.
    it 'falls back to the default when the dates are unusable' do
      fetch(administrator, { since: 'ontem', until: '' })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['period_days']).to eq(30)
    end

    # Cada requisição varre o log duas vezes, a janela pedida e a anterior, e
    # ninguém digitando 2015 no calendário deveria varrer a instalação inteira.
    it 'caps a window nobody should be able to ask for' do
      fetch(administrator, { days: 4000 })

      expect(response.parsed_body['period_days']).to eq(Ai::Reports::Period::MAX_DAYS)
    end
  end
end
