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
    it 'accepts the ranges the screen offers' do
      fetch(administrator, { days: 7 })

      expect(response.parsed_body['period_days']).to eq(7)
    end

    # Snapped rather than clamped, so nobody can quote a window the screen
    # cannot reproduce.
    it 'snaps anything else back to the default' do
      fetch(administrator, { days: 400 })

      expect(response.parsed_body['period_days']).to eq(30)
    end
  end
end
