require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Whatsapp::StatusFoldersController', type: :request do
  let(:account) { create(:account) }
  let(:headers) { create(:user, account: account, role: :administrator).create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/whatsapp/status_folders" }

  it 'creates, counts, renames and deletes folders without deleting the campaigns' do
    post base, params: { name: 'Datas comemorativas', color: '#1F7A3D' }, headers: headers, as: :json
    folder_id = response.parsed_body['id']
    campaign = create(:whatsapp_status_campaign, account: account, folder_id: folder_id)
    create(:whatsapp_status_campaign, account: account)

    get base, headers: headers
    expect(response.parsed_body['payload'].first).to include('name' => 'Datas comemorativas', 'campaigns_count' => 1)
    expect(response.parsed_body['meta']).to eq('unfiled_count' => 1, 'total_count' => 2)

    patch "#{base}/#{folder_id}", params: { name: 'Feriados' }, headers: headers, as: :json
    expect(response.parsed_body['name']).to eq('Feriados')

    delete "#{base}/#{folder_id}", headers: headers
    expect(campaign.reload.folder_id).to be_nil
  end
end
