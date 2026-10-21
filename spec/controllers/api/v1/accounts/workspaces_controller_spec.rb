require 'rails_helper'

RSpec.describe 'Workspace API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:image) { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }

  describe 'PATCH /api/v1/accounts/:account_id/workspace' do
    it 'lets an admin upload a cover and a logo', :aggregate_failures do
      patch "/api/v1/accounts/#{account.id}/workspace", params: { cover: image, logo: image }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(account.reload.cover).to be_attached
      expect(account.logo).to be_attached
      expect(response.parsed_body['cover_url']).to be_present
      expect(response.parsed_body['logo_url']).to be_present
    end

    it 'saves and clears the cover theme', :aggregate_failures do
      patch "/api/v1/accounts/#{account.id}/workspace", params: { cover_theme: 'sunset' }, headers: admin.create_new_auth_token, as: :json
      expect(account.reload.cover_theme).to eq('sunset')
      expect(response.parsed_body['settings']['cover_theme']).to eq('sunset')

      patch "/api/v1/accounts/#{account.id}/workspace", params: { cover_theme: '' }, headers: admin.create_new_auth_token, as: :json
      expect(account.reload.cover_theme).to be_nil
    end

    it 'rejects an unknown theme' do
      patch "/api/v1/accounts/#{account.id}/workspace", params: { cover_theme: 'neon' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.cover_theme).to be_nil
    end

    it 'rejects a file that is not an image' do
      pdf = fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')

      patch "/api/v1/accounts/#{account.id}/workspace", params: { cover: pdf }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.cover).not_to be_attached
    end

    it 'refuses an agent' do
      patch "/api/v1/accounts/#{account.id}/workspace", params: { cover_theme: 'sunset' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(account.reload.cover_theme).to be_nil
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/workspace' do
    before { account.cover.attach(image) }

    it 'removes the cover image' do
      delete "/api/v1/accounts/#{account.id}/workspace", params: { attachment: 'cover' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account.reload.cover).not_to be_attached
    end

    it 'refuses an agent' do
      delete "/api/v1/accounts/#{account.id}/workspace", params: { attachment: 'cover' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(account.reload.cover).to be_attached
    end
  end

  describe 'vertical of the activity' do
    let!(:vertical) { Vertical.create!(key: 'beauty_salon', name: 'Salão de beleza') }

    before { vertical.vertical_statuses.create!(title: 'agendado', color: '#22C55E') }

    it 'lists the verticals with the one in use' do
      account.custom_attributes['vertical_template'] = 'beauty_salon'
      account.save!

      get "/api/v1/accounts/#{account.id}/workspace", headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq(
        'vertical' => 'beauty_salon',
        'verticals' => [{ 'key' => 'beauty_salon', 'name' => 'Salão de beleza', 'description' => nil }]
      )
    end

    it 'applies the chosen vertical to the workspace', :aggregate_failures do
      patch "/api/v1/accounts/#{account.id}/workspace", params: { vertical: 'beauty_salon' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['vertical']).to eq('beauty_salon')
      expect(account.reload.custom_attributes['vertical_template']).to eq('beauty_salon')
      expect(account.labels.pluck(:title)).to include('agendado')
    end

    it 'does not let an agent change the vertical' do
      patch "/api/v1/accounts/#{account.id}/workspace", params: { vertical: 'beauty_salon' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(account.reload.custom_attributes).not_to have_key('vertical_template')
    end
  end

  it 'lists the cover and vertical of every account in the user profile', :aggregate_failures do
    Vertical.create!(key: 'ecommerce', name: 'E-commerce')
    account.update!(cover_theme: 'ocean', custom_attributes: { 'vertical_template' => 'ecommerce' })

    get '/api/v1/profile', headers: admin.create_new_auth_token, as: :json

    entry = response.parsed_body['accounts'].find { |a| a['id'] == account.id }
    expect(entry).to include('cover_theme' => 'ocean', 'vertical' => 'ecommerce', 'vertical_name' => 'E-commerce')
    expect(entry).to include('cover_url', 'logo_url')
  end
end
