require 'rails_helper'

RSpec.describe 'Broadcasts smart dispatch API', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:quiet) { create(:contact, account: account, name: 'Carla Dias', phone_number: '+5531900000001') }
  let(:opted) { create(:contact, account: account, phone_number: '+5531900000002', custom_attributes: { 'opt_out_disparos' => true }) }
  let(:broadcast) do
    create(:broadcast, account: account, inbox: inbox, audience: { 'contact_ids' => [quiet.id, opted.id] },
                       message: { 'messages' => [{ 'text' => 'Oi {primeiro_nome}, sua {servico}?' }] })
  end
  let(:base) { "/api/v1/accounts/#{account.id}/broadcasts" }

  it 'pré-visualiza quem recebe, quem fica de fora e o texto de cada um' do
    get "#{base}/#{broadcast.id}/audience_preview", headers: admin.create_new_auth_token

    body = response.parsed_body
    expect(body).to include('count' => 2, 'new_count' => 2, 'eligible_count' => 1)
    expect(body['excluded']).to eq('opted_out' => 1, 'recent_activity' => 0)
    row = body['sample'].find { |item| item['contact_id'] == quiet.id }
    expect(row).to include('text' => 'Oi Carla, sua ?', 'missing_variables' => ['servico'], 'skip_reason' => nil)
    expect(body['estimate']).to include('per_hour' => 30, 'per_day' => 150, 'days' => 1, 'window_start' => 9, 'window_end' => 19)
  end

  it 'lançar com horário futuro deixa agendado' do
    broadcast.update!(scheduled_at: 2.days.from_now)

    post "#{base}/#{broadcast.id}/launch", headers: admin.create_new_auth_token

    expect(broadcast.reload).to be_status_scheduled
    expect(enqueued_jobs.last[:job]).to eq(Broadcasts::DispatchJob)
  end

  it 'pausar grava o motivo manual e o relatório traz as contagens' do
    create(:broadcast_recipient, broadcast: broadcast, contact: quiet, status: :sent, sent_at: Time.current, replied_at: Time.current)
    create(:broadcast_recipient, broadcast: broadcast, contact: opted, status: :skipped, skip_reason: 'opted_out')
    post "#{base}/#{broadcast.id}/pause", headers: admin.create_new_auth_token

    get "#{base}/#{broadcast.id}/recipients", headers: admin.create_new_auth_token

    body = response.parsed_body
    expect(body['pause_reason']).to eq('manual')
    expect(body['counts']).to include('sent' => 1, 'replied' => 1, 'skipped' => 1, 'skipped_by_reason' => { 'opted_out' => 1 })
  end

  it 'pede variações à IA da conta' do
    allow(Broadcasts::VariationSuggestionService).to receive(:new).and_return(instance_double(Broadcasts::VariationSuggestionService,
                                                                                              perform: %w[A B]))

    post "#{base}/variations", params: { text: 'Oi' }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('variations' => %w[A B])
  end
end
