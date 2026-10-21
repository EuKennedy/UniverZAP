require 'rails_helper'

RSpec.describe Webhooks::WahaEventsJob do
  let(:account) { create(:account) }
  let!(:inbox) do
    create(:channel_api, account: account,
                         additional_attributes: { 'source' => 'waha', 'session_name' => 'u5-salao' }).reload.inbox
  end

  def event(from:, notify_name: 'Maria')
    {
      'session' => 'u5-salao',
      'event' => 'message',
      'payload' => {
        'id' => "false_#{from}_#{SecureRandom.hex(4)}",
        'from' => from, 'to' => '5511888880000@c.us', 'fromMe' => false,
        'body' => 'oi, vi o anúncio', 'timestamp' => Time.current.to_i, 'hasMedia' => false,
        '_data' => { 'notifyName' => notify_name }.compact
      }
    }
  end

  # Lead de anúncio do Instagram/Facebook: a WAHA manda só o LID. Antes, os
  # dígitos viravam phone_number "+159519548166205", um número que não existe.
  it 'creates a LID-only contact by identifier, with no phone number, and asks for the number later' do
    expect { described_class.perform_now(event(from: '159519548166205@lid')) }
      .to have_enqueued_job(Whatsapp::WahaResolveLidJob)

    contact = account.contacts.find_by(identifier: '159519548166205@lid')
    expect(contact).to have_attributes(name: 'Maria', phone_number: nil)
    expect(contact.custom_attributes).to include('waha_whatsapp_lid' => '159519548166205@lid')
    expect(inbox.contact_inboxes.find_by(source_id: '159519548166205@lid').contact).to eq(contact)
    expect(inbox.messages.last.content).to eq('oi, vi o anúncio')
  end

  it 'names a LID-only contact without push name as having no number' do
    described_class.perform_now(event(from: '159519548166205@lid', notify_name: nil))

    expect(account.contacts.find_by(identifier: '159519548166205@lid').name).to eq('Contact without phone number')
  end

  it 'still creates contacts from a regular phone JID with the phone number' do
    described_class.perform_now(event(from: '5511999990000@c.us'))

    expect(account.contacts.find_by(phone_number: '+5511999990000')).to have_attributes(name: 'Maria')
  end
end
