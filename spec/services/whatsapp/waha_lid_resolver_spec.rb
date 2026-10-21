require 'rails_helper'

RSpec.describe Whatsapp::WahaLidResolver do
  let(:account) { create(:account) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:lid) { '159519548166205@lid' }
  let(:inbox) do
    create(:channel_api, account: account,
                         additional_attributes: { 'source' => 'waha', 'session_name' => 'u5-salao' }).reload.inbox
  end

  # Como a ponte WAHA cria um lead de anúncio: identifier e nome são o LID.
  def lid_contact(name: lid)
    contact = create(:contact, account: account, name: name, identifier: lid, phone_number: nil,
                               custom_attributes: { 'waha_whatsapp_lid' => lid })
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: lid)
    contact
  end

  def stub_lid(phone_jid)
    stub_request(:get, 'https://waha.test/api/u5-salao/lids/159519548166205')
      .to_return(status: 200, headers: json, body: { lid: lid, pn: phone_jid }.to_json)
  end

  def stub_waha_contact(chat_id, body)
    stub_request(:get, "https://waha.test/api/contacts?session=u5-salao&contactId=#{chat_id}")
      .to_return(status: 200, headers: json, body: body.to_json)
  end

  def resolve(contact)
    with_modified_env(WAHA_BASE_URL: 'https://waha.test', WAHA_API_KEY: 'k') { described_class.new(contact).perform }
  end

  it 'records the phone number and JID when WAHA knows the number behind the LID' do
    contact = lid_contact
    stub_lid('5511999990000@c.us')
    stub_waha_contact('5511999990000@c.us', { id: '5511999990000@c.us', pushname: 'Maria' })

    expect(resolve(contact)).to eq(:resolved)
    expect(contact.reload).to have_attributes(phone_number: '+5511999990000', name: 'Maria', identifier: lid)
    expect(contact.custom_attributes).to include('waha_whatsapp_jid' => '5511999990000@c.us', 'waha_whatsapp_lid' => lid)
  end

  it 'falls back to the phone number as name when WhatsApp has no push name either' do
    contact = lid_contact
    stub_lid('5511999990000@c.us')
    stub_waha_contact('5511999990000@c.us', {})

    resolve(contact)

    expect(contact.reload.name).to eq('+5511999990000')
  end

  it 'keeps a name an agent typed by hand' do
    contact = lid_contact(name: 'Maria do anúncio')
    stub_lid('5511999990000@c.us')
    stub_waha_contact('5511999990000@c.us', { pushname: 'Mari' })

    resolve(contact)

    expect(contact.reload.name).to eq('Maria do anúncio')
  end

  # Mesma pessoa que já falou pelo número: um contato só, com as conversas das
  # duas origens, em vez do 422 de telefone duplicado.
  it 'merges into the contact that already owns the phone number' do
    existing = create(:contact, account: account, name: 'Maria', phone_number: '+5511999990000',
                                custom_attributes: { 'waha_whatsapp_jid' => '5511999990000@c.us' })
    contact = lid_contact
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact,
                                         contact_inbox: contact.contact_inboxes.first)
    stub_lid('5511999990000@c.us')

    expect(resolve(contact)).to eq(:merged)

    expect(Contact.exists?(contact.id)).to be(false)
    expect(conversation.reload.contact).to eq(existing)
    expect(existing.reload).to have_attributes(name: 'Maria', phone_number: '+5511999990000', identifier: lid)
    expect(existing.custom_attributes).to include('waha_whatsapp_jid' => '5511999990000@c.us', 'waha_whatsapp_lid' => lid)
  end

  context 'when WAHA does not know the number yet' do
    before { stub_lid(nil) }

    it 'replaces the raw LID name with the push name' do
      contact = lid_contact
      stub_waha_contact(lid, { id: lid, pushname: 'Maria' })

      expect(resolve(contact)).to eq(:unresolved)
      expect(contact.reload).to have_attributes(name: 'Maria', phone_number: nil)
    end

    it 'labels the contact as having no number when there is no push name' do
      contact = lid_contact
      stub_waha_contact(lid, {})

      resolve(contact)

      expect(contact.reload.name).to eq('Contact without phone number')
    end

    it 'survives a WAHA error without touching the contact' do
      contact = lid_contact(name: 'Maria')
      stub_request(:get, 'https://waha.test/api/u5-salao/lids/159519548166205').to_return(status: 500, body: 'boom')

      expect(resolve(contact)).to eq(:unresolved)
      expect(contact.reload.name).to eq('Maria')
    end
  end

  it 'skips contacts that are not LID-only or have no WAHA inbox' do
    with_phone = create(:contact, account: account, identifier: lid, phone_number: '+5511999990000')
    not_waha = create(:contact, account: account, identifier: '1@lid')

    expect(resolve(with_phone)).to eq(:skipped)
    expect(resolve(not_waha)).to eq(:skipped)
  end
end
