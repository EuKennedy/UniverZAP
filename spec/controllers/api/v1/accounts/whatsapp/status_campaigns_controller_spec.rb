require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Whatsapp::StatusCampaignsController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:headers) { administrator.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/whatsapp/status_campaigns" }
  let(:inbox) do
    create(:channel_api, account: account, additional_attributes: { 'source' => 'waha', 'session_name' => 'u1-loja' }).reload.inbox
  end
  let(:folder) { create(:whatsapp_status_folder, account: account, name: 'Promoções') }
  let(:steps) do
    [{ kind: 'text', body: 'Agenda aberta!', day_offset: 0, time_of_day: '09:00', repost_count: 1, repost_interval_hours: 24 },
     { kind: 'text', body: 'Última chamada', day_offset: 2, time_of_day: '18:00' }]
  end

  def create_campaign(extra = {})
    post base, params: { name: 'Semana da escova', folder_id: folder.id, inbox_ids: [inbox.id], starts_on: 1.day.from_now.to_date,
                         cycle_days: 7, time_zone: 'America/Sao_Paulo', steps: steps }.merge(extra), headers: headers, as: :json
    response.parsed_body
  end

  it 'creates a campaign with its flow as a draft that schedules nothing' do
    body = create_campaign

    expect(body).to include('name' => 'Semana da escova', 'status' => 'draft', 'folder_name' => 'Promoções', 'steps_count' => 2)
    expect(body['steps'].pluck('body')).to eq(['Agenda aberta!', 'Última chamada'])
    expect(account.whatsapp_status_posts).to be_empty
  end

  it 'previews the next posts before activating' do
    id = create_campaign['id']

    get "#{base}/#{id}/preview", headers: headers

    expect(response.parsed_body['payload'].first(3).pluck('body')).to eq(['Agenda aberta!', 'Agenda aberta!', 'Última chamada'])
  end

  it 'activating schedules the flow and pausing takes the future posts out' do
    id = create_campaign['id']

    post "#{base}/#{id}/activate", headers: headers
    expect(response.parsed_body['status']).to eq('active')
    expect(account.whatsapp_status_posts.status_scheduled.where(campaign_id: id).count).to be >= 3

    post "#{base}/#{id}/pause", headers: headers
    expect(response.parsed_body['status']).to eq('paused')
    expect(account.whatsapp_status_posts.where(campaign_id: id)).to be_empty
  end

  it 'refuses to activate a campaign without steps' do
    id = create_campaign(steps: [])['id']

    post "#{base}/#{id}/activate", headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'replaces the steps on update and replans an active campaign' do
    id = create_campaign['id']
    post "#{base}/#{id}/activate", headers: headers
    first_step = WhatsappStatusCampaign.find(id).steps.first

    patch "#{base}/#{id}", params: { steps: [{ id: first_step.id, kind: 'text', body: 'Novo texto', day_offset: 0, time_of_day: '10:00' }] },
                           headers: headers, as: :json

    expect(response.parsed_body['steps'].pluck('id', 'body')).to eq([[first_step.id, 'Novo texto']])
    expect(account.whatsapp_status_posts.status_scheduled.where(campaign_id: id).pluck(:body).uniq).to eq(['Novo texto'])
  end

  it 'filters by folder, including campaigns without one' do
    create_campaign
    create(:whatsapp_status_campaign, account: account, name: 'Solta')

    get base, params: { folder_id: 'none' }, headers: headers
    expect(response.parsed_body['payload'].pluck('name')).to eq(['Solta'])

    get base, params: { folder_id: folder.id }, headers: headers
    expect(response.parsed_body['payload'].pluck('name')).to eq(['Semana da escova'])
  end

  it 'keeps the posted history when a campaign is deleted' do
    id = create_campaign['id']
    posted = create(:whatsapp_status_post, account: account, campaign_id: id, status: :published, inbox_ids: [inbox.id])

    delete "#{base}/#{id}", headers: headers

    expect(posted.reload.campaign_id).to be_nil
  end

  it 'refuses an agent' do
    get base, headers: create(:user, account: account, role: :agent).create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end
end
