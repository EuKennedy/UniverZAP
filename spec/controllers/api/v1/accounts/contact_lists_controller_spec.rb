require 'rails_helper'

RSpec.describe 'Contact lists API', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/contact_lists" }
  let(:waha_inbox) do
    create(:channel_api, account: account, additional_attributes: { 'source' => 'waha', 'session_name' => 'u5-salao' }).reload.inbox
  end
  let(:group_contact) { create(:contact, account: account, name: 'Clientes VIP', identifier: '120363000000000001@g.us') }
  let(:group_conversation) { create(:conversation, account: account, inbox: waha_inbox, contact: group_contact) }

  it 'cria lista manual, adiciona e remove membros' do
    contact = create(:contact, account: account, phone_number: '+5531988881111')
    post base, params: { contact_list: { name: 'VIP', description: 'Clientes fiéis' } }, headers: admin.create_new_auth_token
    id = response.parsed_body['id']

    post "#{base}/#{id}/add_members", params: { contact_ids: [contact.id] }, headers: admin.create_new_auth_token
    expect(response.parsed_body).to include('added' => 1, 'members_count' => 1)

    get "#{base}/#{id}/members", headers: agent.create_new_auth_token
    member = response.parsed_body['payload'].first
    expect(member).to include('name' => contact.name, 'phone' => '+5531988881111', 'status' => 'active', 'cold' => false)

    post "#{base}/#{id}/remove_members", params: { member_ids: [member['id']] }, headers: admin.create_new_auth_token
    expect(response.parsed_body['members_count']).to eq(0)
  end

  it 'cria lista por filtro de etiqueta como foto' do
    label = create(:label, account: account, title: 'vip')
    tagged = create(:contact, account: account)
    tagged.add_labels(['vip'])

    post base, params: { contact_list: { name: 'Etiqueta VIP', source: 'filter', label_ids: [label.id] } }, headers: admin.create_new_auth_token

    expect(response.parsed_body).to include('source' => 'filter', 'members_count' => 1)
  end

  it 'agente vê mas não cria' do
    post base, params: { contact_list: { name: 'x' } }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)

    get base, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
  end

  it 'não mostra lista de outra conta' do
    foreign = create(:contact_list)

    get "#{base}/#{foreign.id}", headers: admin.create_new_auth_token

    expect(response).to have_http_status(:not_found)
  end

  it 'importa CSV e devolve o resumo' do
    list = create(:contact_list, account: account, source: 'csv')

    post "#{base}/#{list.id}/import_csv", params: { content: "Ana;31988881111\n", cold: 'true' }, headers: admin.create_new_auth_token

    expect(response.parsed_body).to include('added' => 1, 'created' => 1, 'members_count' => 1)
  end

  it 'lista os grupos extraíveis e extrai em segundo plano, reaproveitando a lista do grupo' do
    group_conversation
    get "#{base}/groups", headers: admin.create_new_auth_token
    expect(response.parsed_body['payload'].first).to include('display_id' => group_conversation.display_id, 'name' => 'Clientes VIP',
                                                             'list_id' => nil)

    post "#{base}/extract_group", params: { conversation_id: group_conversation.display_id }, headers: admin.create_new_auth_token
    body = response.parsed_body
    expect(body).to include('source' => 'group', 'status' => 'importing', 'group_identifier' => '120363000000000001@g.us')
    expect(enqueued_jobs.last[:job]).to eq(ContactLists::GroupExtractionJob)

    ContactList.find(body['id']).update!(status: 'ready')
    post "#{base}/extract_group", params: { conversation_id: group_conversation.display_id }, headers: admin.create_new_auth_token
    expect(response.parsed_body['id']).to eq(body['id'])
  end

  it 'recusa extrair conversa que não é grupo e atualizar lista que não é de grupo' do
    conversation = create(:conversation, account: account, inbox: waha_inbox)
    post "#{base}/extract_group", params: { conversation_id: conversation.display_id }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)

    list = create(:contact_list, account: account)
    post "#{base}/#{list.id}/refresh", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'mescla, deduplica, exporta e traz os números da conta' do
    first = create(:contact_list, account: account)
    second = create(:contact_list, account: account)
    create(:contact_list_member, contact_list: first, contact: create(:contact, account: account, phone_number: '+5531988881111'))
    cold = create(:contact, account: account, phone_number: '+5531988882222', custom_attributes: { 'consentimento_disparo' => false })
    create(:contact_list_member, contact_list: second, contact: cold)

    post "#{base}/merge", params: { list_ids: [first.id, second.id], name: 'Todas' }, headers: admin.create_new_auth_token
    merged = response.parsed_body
    expect(merged).to include('name' => 'Todas', 'members_count' => 2)
    expect(merged['summary']).to include('sendable' => 1, 'unconsented' => 1)

    post "#{base}/#{merged['id']}/deduplicate", headers: admin.create_new_auth_token
    expect(response.parsed_body['removed']).to eq(0)

    get "#{base}/#{merged['id']}/export", headers: agent.create_new_auth_token
    expect(response.headers['Content-Type']).to include('text/csv')

    get "#{base}/stats", headers: agent.create_new_auth_token
    expect(response.parsed_body).to include('lists' => 3, 'unconsented' => 1)
  end

  describe 'confirmação no disparo' do
    let(:list) { create(:contact_list, account: account) }
    let(:cold) { create(:contact, account: account, phone_number: '+5531988882222', custom_attributes: { 'consentimento_disparo' => false }) }
    let(:broadcast) { create(:broadcast, account: account, audience: { 'contact_list_ids' => [list.id] }) }

    before { create(:contact_list_member, contact_list: list, contact: cold) }

    it 'a pré-visualização conta quem nunca falou e só inclui depois da confirmação' do
      get "/api/v1/accounts/#{account.id}/broadcasts/#{broadcast.id}/audience_preview", headers: admin.create_new_auth_token
      expect(response.parsed_body).to include('count' => 0, 'unconsented_count' => 1, 'cold_contacts_confirmed' => false)

      patch "/api/v1/accounts/#{account.id}/broadcasts/#{broadcast.id}",
            params: { broadcast: { audience: { contact_list_ids: [list.id] }, confirm_cold_contacts: true } },
            headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['cold_contacts_confirmed_at']).to be_present
      expect(broadcast.reload.cold_contacts_confirmed_by_id).to eq(admin.id)

      get "/api/v1/accounts/#{account.id}/broadcasts/#{broadcast.id}/audience_preview", headers: admin.create_new_auth_token
      expect(response.parsed_body).to include('count' => 1, 'unconsented_count' => 1, 'cold_contacts_confirmed' => true)
    end

    it 'duplicar não leva a confirmação' do
      broadcast.update!(cold_contacts_confirmed_at: Time.current)

      post "/api/v1/accounts/#{account.id}/broadcasts/#{broadcast.id}/duplicate", headers: admin.create_new_auth_token

      expect(response.parsed_body['cold_contacts_confirmed_at']).to be_nil
    end
  end
end
