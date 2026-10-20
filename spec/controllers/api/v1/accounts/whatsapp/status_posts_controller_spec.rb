require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Whatsapp::StatusPostsController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/whatsapp/status_posts" }
  let(:headers) { administrator.create_new_auth_token }
  let(:waha_inbox) do
    create(:channel_api, account: account, additional_attributes: { 'source' => 'waha', 'session_name' => 'u1-loja' }).reload.inbox
  end
  let(:image_blob) do
    ActiveStorage::Blob.create_and_upload!(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'a.png', content_type: 'image/png')
  end

  describe 'POST /status_posts' do
    it 'saves a draft without publishing anything' do
      expect do
        post base, params: { intent: 'draft', kind: 'text', body: 'Oi', inbox_ids: [] }, headers: headers, as: :json
      end.not_to have_enqueued_job(Whatsapp::StatusPosts::PublishJob)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('draft')
      expect(WhatsappStatusPost.last.user).to eq(administrator)
    end

    it 'publishes now in the background' do
      expect do
        post base, params: { intent: 'publish', kind: 'image', body: 'Chegou', blob_id: image_blob.signed_id, inbox_ids: [waha_inbox.id] },
                   headers: headers, as: :json
      end.to have_enqueued_job(Whatsapp::StatusPosts::PublishJob)

      expect(response.parsed_body).to include('status' => 'publishing', 'kind' => 'image')
      expect(response.parsed_body.dig('media', 'content_type')).to eq('image/png')
    end

    it 'schedules for later' do
      at = 2.hours.from_now.change(usec: 0)
      post base, params: { intent: 'schedule', kind: 'text', body: 'Amanhã tem', inbox_ids: [waha_inbox.id], scheduled_at: at.iso8601 },
                 headers: headers, as: :json

      expect(response.parsed_body['status']).to eq('scheduled')
      expect(Time.zone.parse(response.parsed_body['scheduled_at'])).to eq(at)
    end

    it 'explains why a status cannot go out' do
      post base, params: { intent: 'publish', kind: 'text', body: '', inbox_ids: [] }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to include('body', 'inbox_ids')
    end

    it 'refuses an unknown upload' do
      post base, params: { intent: 'draft', kind: 'image', blob_id: 'nope' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses an agent' do
      post base, params: { intent: 'draft', kind: 'text', body: 'Oi' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /status_posts' do
    it 'lists only this account history with each connection result' do
      mine = create(:whatsapp_status_post, account: account, status: :published, inbox_ids: [waha_inbox.id])
      mine.deliveries.create!(inbox: waha_inbox, inbox_name: 'Loja', status: :failed, error_message: 'offline')
      create(:whatsapp_status_post, account: create(:account))

      get base, headers: headers, as: :json

      payload = response.parsed_body['payload']
      expect(payload.pluck('id')).to eq([mine.id])
      expect(payload.first['deliveries'].first).to include('inbox_name' => 'Loja', 'status' => 'failed', 'error_message' => 'offline')
    end
  end

  describe 'PATCH/DELETE on a posted status' do
    let(:published) { create(:whatsapp_status_post, account: account, status: :published, inbox_ids: [waha_inbox.id]) }

    it 'refuses to edit what already went out' do
      patch "#{base}/#{published.id}", params: { intent: 'draft', body: 'outro' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(published.reload.body).to eq('Agenda aberta para sábado')
    end

    it 'cancels a scheduled status' do
      scheduled = create(:whatsapp_status_post, account: account, status: :scheduled, inbox_ids: [waha_inbox.id], scheduled_at: 1.day.from_now)

      delete "#{base}/#{scheduled.id}", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(WhatsappStatusPost.exists?(scheduled.id)).to be(false)
    end
  end

  describe 'POST /status_posts/:id/retry' do
    it 'puts only the failed connections back in line' do
      post_record = create(:whatsapp_status_post, account: account, status: :partially_published, inbox_ids: [waha_inbox.id])
      sent = post_record.deliveries.create!(inbox: waha_inbox, inbox_name: 'A', status: :sent)
      failed = post_record.deliveries.create!(inbox: waha_inbox, inbox_name: 'B', status: :failed, error_message: 'x')

      expect { post "#{base}/#{post_record.id}/retry", headers: headers, as: :json }
        .to have_enqueued_job(Whatsapp::StatusPosts::PublishJob).with(post_record.id)

      expect([sent.reload.status, failed.reload.status]).to eq(%w[sent pending])
      expect(post_record.reload).to be_status_publishing
    end
  end

  describe 'POST /status_posts/suggest' do
    it 'returns the assistant suggestion' do
      allow(Whatsapp::StatusPosts::SuggestionService).to receive(:new).and_return(instance_double(Whatsapp::StatusPosts::SuggestionService,
                                                                                                  perform: 'Sábado tem horário!'))

      post "#{base}/suggest", params: { prompt: 'agenda de sábado', kind: 'text' }, headers: headers, as: :json

      expect(response.parsed_body['text']).to eq('Sábado tem horário!')
    end

    it 'says when the account has no active assistant' do
      account.ai_assistants.update_all(active: false) # rubocop:disable Rails/SkipsModelValidations
      post "#{base}/suggest", params: { prompt: 'agenda de sábado' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('inbox.whatsapp.waha.suggestion_no_assistant'))
    end
  end
end
