require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Whatsapp::StatusTemplatesController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/whatsapp/status_templates" }

  it 'creates, lists, updates and removes templates of the account' do
    post base, params: { name: 'Agenda aberta', body: 'Sábado com horários', background_color: '#1F7A3D', font: 2 },
               headers: administrator.create_new_auth_token, as: :json
    id = response.parsed_body['id']
    create(:whatsapp_status_template, account: create(:account))

    get base, headers: administrator.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('name')).to eq(['Agenda aberta'])

    patch "#{base}/#{id}", params: { body: 'Domingo também' }, headers: administrator.create_new_auth_token, as: :json
    expect(response.parsed_body['body']).to eq('Domingo também')

    delete "#{base}/#{id}", headers: administrator.create_new_auth_token, as: :json
    expect(account.whatsapp_status_templates).to be_empty
  end

  it 'refuses a duplicated name' do
    create(:whatsapp_status_template, account: account, name: 'Promo')

    post base, params: { name: 'Promo', body: 'x' }, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'refuses an agent' do
    get base, headers: create(:user, account: account, role: :agent).create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
