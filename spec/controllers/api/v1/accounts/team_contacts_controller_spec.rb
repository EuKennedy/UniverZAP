require 'rails_helper'

RSpec.describe 'Team contacts API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:staff) { create(:contact, account: account, name: 'Marcela') }
  let!(:chat) { create(:conversation, account: account, inbox: inbox, contact: staff) }

  it 'lets an admin put a contact in the team, moving its conversations to the Equipe tab', :aggregate_failures do
    post "/api/v1/accounts/#{account.id}/team_contacts", params: { contact_id: staff.id }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(staff.reload.custom_attributes['equipe']).to be(true)
    expect(chat.reload.is_team).to be(true)

    get "/api/v1/accounts/#{account.id}/team_contacts", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('name')).to eq(['Marcela'])
  end

  it 'takes a contact out of the team' do
    Contacts::TeamService.new(staff).add

    delete "/api/v1/accounts/#{account.id}/team_contacts/#{staff.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(staff.reload.custom_attributes).not_to have_key('equipe')
    expect(chat.reload.is_team).to be(false)
  end

  it 'refuses an agent' do
    post "/api/v1/accounts/#{account.id}/team_contacts", params: { contact_id: staff.id }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(chat.reload.is_team).to be(false)
  end
end
