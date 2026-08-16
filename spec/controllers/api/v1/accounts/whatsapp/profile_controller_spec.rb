require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Whatsapp::ProfileController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:base) { "/api/v1/accounts/#{account.id}/whatsapp/profile" }

  let(:waha_inbox) do
    create(:channel_api, account: account,
                         additional_attributes: { 'source' => 'waha', 'session_name' => 'u1-loja' }).reload.inbox
  end

  let(:image_blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png'
    )
  end

  around do |example|
    with_modified_env(WAHA_BASE_URL: 'https://waha.test', WAHA_API_KEY: 'k') { example.run }
  end

  describe 'GET /whatsapp/profile/inboxes' do
    it 'lists only the WAHA inboxes of the authenticated account' do
      waha_inbox
      create(:inbox, account: account, name: 'Site')
      create(:channel_api, account: create(:account),
                           additional_attributes: { 'source' => 'waha', 'session_name' => 'u2-loja' })

      get "#{base}/inboxes", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([waha_inbox.id])
    end

    it 'refuses an agent' do
      get "#{base}/inboxes", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /whatsapp/profile' do
    it 'returns the profile of the number bound to the inbox' do
      stub_request(:get, 'https://waha.test/api/u1-loja/profile')
        .to_return(status: 200, headers: json, body: { id: '55@c.us', name: 'Loja da Ana', picture: 'https://cdn/p.jpg' }.to_json)

      get base, params: { inbox_id: waha_inbox.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['name']).to eq('Loja da Ana')
    end

    # O bug mais grave que este módulo poderia embarcar: aceitar a sessão vinda
    # do request faria o painel de uma conta operar o número de outra.
    it 'ignores a session_name smuggled in the request and uses the one bound to the inbox' do
      stub_request(:get, %r{https://waha\.test/api/.+/profile}).to_return(status: 200, headers: json, body: '{}')

      get base, params: { inbox_id: waha_inbox.id, session_name: 'default' },
                headers: administrator.create_new_auth_token, as: :json

      expect(a_request(:get, 'https://waha.test/api/default/profile')).not_to have_been_made
      expect(a_request(:get, 'https://waha.test/api/u1-loja/profile')).to have_been_made
    end

    it 'returns 404 for an inbox that belongs to another account' do
      stranger = create(:channel_api, account: create(:account),
                                      additional_attributes: { 'source' => 'waha', 'session_name' => 'u2-loja' }).reload.inbox

      get base, params: { inbox_id: stranger.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(a_request(:get, 'https://waha.test/api/u2-loja/profile')).not_to have_been_made
    end

    it 'rejects an inbox that is not connected to WAHA' do
      inbox = create(:inbox, account: account)

      get base, params: { inbox_id: inbox.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # A WAHA cair não pode virar 500: o operador precisa ler o motivo.
    it 'reports a WAHA outage as a handled error' do
      stub_request(:get, 'https://waha.test/api/u1-loja/profile')
        .to_return(status: 500, body: { message: 'session is not working' }.to_json)

      get base, params: { inbox_id: waha_inbox.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('session is not working')
    end

    it 'refuses an agent' do
      get base, params: { inbox_id: waha_inbox.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PUT /whatsapp/profile/name and /about' do
    it 'changes the name' do
      stub_request(:put, 'https://waha.test/api/u1-loja/profile/name').to_return(status: 200, headers: json, body: '{}')

      put "#{base}/name", params: { inbox_id: waha_inbox.id, name: 'Loja da Ana' },
                          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(a_request(:put, 'https://waha.test/api/u1-loja/profile/name')
        .with(body: { name: 'Loja da Ana' }.to_json)).to have_been_made
    end

    it 'changes the about text' do
      stub_request(:put, 'https://waha.test/api/u1-loja/profile/status').to_return(status: 200, headers: json, body: '{}')

      put "#{base}/about", params: { inbox_id: waha_inbox.id, about: 'Aberto das 9h às 18h' },
                           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(a_request(:put, 'https://waha.test/api/u1-loja/profile/status')).to have_been_made
    end

    it 'refuses an agent' do
      put "#{base}/name", params: { inbox_id: waha_inbox.id, name: 'X' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'picture' do
    it 'sends the uploaded file to WAHA as a url it can download' do
      stub_request(:put, 'https://waha.test/api/u1-loja/profile/picture').to_return(status: 200, headers: json, body: '{}')

      put "#{base}/picture", params: { inbox_id: waha_inbox.id, blob_id: image_blob.signed_id },
                             headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(a_request(:put, 'https://waha.test/api/u1-loja/profile/picture')
        .with { |req| JSON.parse(req.body).dig('file', 'url').present? }).to have_been_made
    end

    it 'rejects a file that is not an image' do
      pdf = ActiveStorage::Blob.create_and_upload!(
        io: Rails.root.join('spec/assets/sample.pdf').open, filename: 's.pdf', content_type: 'application/pdf'
      )

      put "#{base}/picture", params: { inbox_id: waha_inbox.id, blob_id: pdf.signed_id },
                             headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects an unknown upload instead of asking WAHA to fetch nothing' do
      put "#{base}/picture", params: { inbox_id: waha_inbox.id, blob_id: 'not-a-signed-id' },
                             headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'removes the picture' do
      stub_request(:delete, 'https://waha.test/api/u1-loja/profile/picture').to_return(status: 200, headers: json, body: '{}')

      delete "#{base}/picture", params: { inbox_id: waha_inbox.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  describe 'status' do
    it 'publishes a text status' do
      stub_request(:post, 'https://waha.test/api/u1-loja/status/text').to_return(status: 200, headers: json, body: '{}')

      post "#{base}/status/text", params: { inbox_id: waha_inbox.id, text: 'Promoção hoje', background_color: '#38B42F' },
                                  headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(a_request(:post, 'https://waha.test/api/u1-loja/status/text')
        .with(body: { text: 'Promoção hoje', backgroundColor: '#38B42F' }.to_json)).to have_been_made
    end

    it 'refuses a background colour that is not a hex value' do
      post "#{base}/status/text", params: { inbox_id: waha_inbox.id, text: 'Oi', background_color: 'verde' },
                                  headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'publishes an image status with a caption' do
      stub_request(:post, 'https://waha.test/api/u1-loja/status/image').to_return(status: 200, headers: json, body: '{}')

      post "#{base}/status/image", params: { inbox_id: waha_inbox.id, blob_id: image_blob.signed_id, caption: 'Chegou' },
                                   headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(a_request(:post, 'https://waha.test/api/u1-loja/status/image')
        .with { |req| JSON.parse(req.body)['caption'] == 'Chegou' }).to have_been_made
    end

    it 'publishes a video status' do
      video = ActiveStorage::Blob.create_and_upload!(
        io: Rails.root.join('spec/assets/sample.mp4').open, filename: 'v.mp4', content_type: 'video/mp4'
      )
      stub_request(:post, 'https://waha.test/api/u1-loja/status/video').to_return(status: 200, headers: json, body: '{}')

      post "#{base}/status/video", params: { inbox_id: waha_inbox.id, blob_id: video.signed_id },
                                   headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(a_request(:post, 'https://waha.test/api/u1-loja/status/video')).to have_been_made
    end

    it 'returns 404 when the inbox belongs to another account' do
      stranger = create(:channel_api, account: create(:account),
                                      additional_attributes: { 'source' => 'waha', 'session_name' => 'u2-loja' }).reload.inbox

      post "#{base}/status/text", params: { inbox_id: stranger.id, text: 'Oi' },
                                  headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(a_request(:post, 'https://waha.test/api/u2-loja/status/text')).not_to have_been_made
    end

    it 'refuses an agent' do
      post "#{base}/status/text", params: { inbox_id: waha_inbox.id, text: 'Oi' },
                                  headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(a_request(:post, 'https://waha.test/api/u1-loja/status/text')).not_to have_been_made
    end
  end
end
