require 'rails_helper'

RSpec.describe ContactLists::GroupExtractionService do
  let(:account) { create(:account) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:group_id) { '120363000000000001@g.us' }
  let(:waha) { 'https://waha.test/api/u5-salao' }
  let(:inbox) do
    create(:channel_api, account: account, additional_attributes: { 'source' => 'waha', 'session_name' => 'u5-salao' }).reload.inbox
  end
  let(:group_contact) { create(:contact, account: account, name: 'Clientes VIP Lourdes', identifier: group_id) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: group_contact) }
  let(:list) { ContactLists::GroupCatalog.new(account).list_for!(conversation) }

  before do
    stub_request(:get, 'https://waha.test/api/sessions/u5-salao')
      .to_return(status: 200, headers: json, body: { name: 'u5-salao', me: { id: '5531999990000@c.us' } }.to_json)
  end

  def stub_participants(body, version: 'v2')
    path = version == 'v2' ? "#{waha}/groups/#{group_id}/participants/v2" : "#{waha}/groups/#{group_id}/participants"
    stub_request(:get, path).to_return(status: 200, headers: json, body: body.to_json)
  end

  def stub_lid(lid, phone_jid)
    stub_request(:get, "#{waha}/lids/#{lid.delete_suffix('@lid')}")
      .to_return(status: 200, headers: json, body: { lid: lid, pn: phone_jid }.to_json)
  end

  def extract
    with_modified_env(WAHA_BASE_URL: 'https://waha.test', WAHA_API_KEY: 'k') { described_class.new(list).perform }
  end

  it 'cria a lista do grupo com os participantes, sem o número do próprio salão' do
    stub_participants([{ id: '5531988881111@c.us', role: 'admin' }, { id: '5531988882222@c.us', role: 'participant' },
                       { id: '5531999990000@c.us', role: 'superadmin' }])

    extract

    expect(list.reload).to have_attributes(status: 'ready', members_count: 2, source: 'group')
    expect(account.contacts.where(phone_number: %w[+5531988881111 +5531988882222]).count).to eq(2)
    expect(list.members.find_by(wa_id: '5531988881111@c.us').role).to eq('admin')
    expect(account.contacts.find_by(phone_number: '+5531999990000')).to be_nil
  end

  it 'reaproveita contato existente, inclusive gravado sem o nono dígito' do
    old = create(:contact, account: account, name: 'Ana', phone_number: '+553188881111')
    stub_participants([{ id: '553188881111@c.us', role: 'participant' }])
    list

    expect { extract }.not_to(change { account.contacts.count })
    expect(list.members.pluck(:contact_id)).to eq([old.id])
    expect(old.reload.custom_attributes).not_to have_key('consentimento_disparo')
  end

  it 'contato criado pela extração nasce sem consentimento e com a etiqueta do grupo' do
    stub_participants([{ id: '5531988881111@c.us', role: 'participant' }])

    extract

    contact = account.contacts.find_by(phone_number: '+5531988881111')
    expect(contact.custom_attributes['consentimento_disparo']).to be(false)
    expect(contact.label_list).to eq(['grupo-clientes-vip-lourdes'])
    expect(account.labels.find_by(title: 'grupo-clientes-vip-lourdes')).to be_present
    expect(account.custom_attribute_definitions.find_by(attribute_key: 'consentimento_disparo')).to be_checkbox
  end

  it 'resolve @lid pela WAHA e deixa quem não resolve como sem telefone' do
    stub_participants([{ id: '111111111111111@lid', role: 'participant' }, { id: '222222222222222@lid', role: 'participant' }])
    stub_lid('111111111111111@lid', '5531977773333@c.us')
    stub_lid('222222222222222@lid', nil)

    result = extract

    expect(account.contacts.find_by(phone_number: '+5531977773333')).to be_present
    unresolved = list.members.find_by(wa_id: '222222222222222@lid')
    expect(unresolved.contact).to be_nil
    expect(result).to include(no_phone: 1, lids_resolved: 1)
    expect(list.sendable_contact_ids.length).to eq(1)
  end

  it 'liga o participante de LID ao contato que a ponte já tinha criado' do
    lid_contact = create(:contact, account: account, identifier: '333333333333333@lid', name: '333333333333333@lid')
    stub_participants([{ id: '333333333333333@lid', role: 'participant' }])
    stub_lid('333333333333333@lid', '5531966664444@c.us')

    extract

    expect(list.members.first.contact).to eq(lid_contact)
    expect(lid_contact.reload.phone_number).to eq('+5531966664444')
  end

  it 'cai na v1 do GOWS quando a v2 não existe' do
    stub_request(:get, "#{waha}/groups/#{group_id}/participants/v2").to_return(status: 404, body: 'Not Found')
    stub_participants([{ JID: '5531988881111:3@s.whatsapp.net', PhoneNumber: '5531988881111@s.whatsapp.net', LID: '444@lid',
                         IsAdmin: true, IsSuperAdmin: false, DisplayName: 'Bia Souza' }], version: 'v1')

    extract

    member = list.members.first
    expect(member).to have_attributes(wa_id: '5531988881111@c.us', role: 'admin')
    expect(member.contact).to have_attributes(name: 'Bia Souza', phone_number: '+5531988881111')
  end

  it 'na atualização marca quem saiu e quem entrou' do
    stub_participants([{ id: '5531988881111@c.us', role: 'participant' }, { id: '5531988882222@c.us', role: 'participant' }])
    extract
    stub_participants([{ id: '5531988882222@c.us', role: 'participant' }, { id: '5531988883333@c.us', role: 'participant' }])

    result = travel_to(1.hour.from_now) { extract }

    expect(result).to include(joined: 1, left: 1)
    expect(list.members.find_by(wa_id: '5531988881111@c.us')).to be_status_left
    newcomer = list.members.find_by(wa_id: '5531988883333@c.us')
    expect(ContactLists::MemberQuery.new_member?(list.reload, newcomer)).to be(true)
    expect(list.members_count).to eq(2)
  end

  it 'avisa o Chatflow de quem entrou e já é cliente, não dos contatos novos do grupo' do
    stub_const('Chatflow::TriggerDispatcher', Class.new { def self.list_entered(_list, _contact); end })
    dispatcher = Chatflow::TriggerDispatcher
    allow(dispatcher).to receive(:list_entered)
    old = create(:contact, account: account, phone_number: '+5531988881111')
    stub_participants([{ id: '5531988881111@c.us', role: 'participant' }, { id: '5531988882222@c.us', role: 'participant' }])

    extract

    expect(dispatcher).to have_received(:list_entered).with(list, old).once
    expect(dispatcher).to have_received(:list_entered).once
  end

  it 'o job marca a lista como falha quando a WAHA erra' do
    stub_request(:get, "#{waha}/groups/#{group_id}/participants/v2").to_return(status: 500, body: 'boom')
    stub_request(:get, "#{waha}/groups/#{group_id}/participants").to_return(status: 500, body: 'boom')

    with_modified_env(WAHA_BASE_URL: 'https://waha.test', WAHA_API_KEY: 'k') { ContactLists::GroupExtractionJob.perform_now(list.id) }

    expect(list.reload.status).to eq('failed')
    expect(list.last_error).to include('500')
  end
end
