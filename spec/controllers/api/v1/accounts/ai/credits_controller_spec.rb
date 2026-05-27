# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Ai::CreditsController', type: :request do
  let(:account) { create(:account) }
  let(:admin)   { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/:account_id/ai/credits' do
    context 'when the user is unauthenticated' do
      it 'returns 401' do
        get "/api/v1/accounts/#{account.id}/ai/credits", as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is authenticated' do
      it 'returns the ledger summary + the static top-up catalogue' do
        get "/api/v1/accounts/#{account.id}/ai/credits",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body).to include(:balance_cents_brl, :threshold_status, :packages, :pricing)
        # Three packages, middle one carries the "popular" anchor badge.
        expect(body[:packages].length).to eq(3)
        expect(body[:packages][1][:badge]).to eq('popular')
        expect(body[:packages].pluck(:checkout_url)).to all(start_with('https://pay.univercart.com/'))
      end
    end
  end
end
