require 'rails_helper'

RSpec.describe 'Ad names API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ad_names/120251719556440201" }

  it 'lets an admin name an ad and clear the name again', :aggregate_failures do
    patch url, params: { name: ' Unhas de gel ', campaign: 'Outubro' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(account.reload.custom_attributes['ad_names']).to eq('120251719556440201' => { 'name' => 'Unhas de gel', 'campaign' => 'Outubro' })

    patch url, params: { name: '', campaign: '' }, headers: admin.create_new_auth_token, as: :json
    expect(account.reload.custom_attributes['ad_names']).to eq({})
  end

  it 'refuses an agent' do
    patch url, params: { name: 'X' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
