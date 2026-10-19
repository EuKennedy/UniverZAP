require 'rails_helper'
require 'rake'

RSpec.describe 'waha:resolve_lids', type: :task do
  let(:account) { create(:account) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:inbox) do
    create(:channel_api, account: account,
                         additional_attributes: { 'source' => 'waha', 'session_name' => 'u5-salao' }).reload.inbox
  end

  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task['waha:resolve_lids'].reenable
  end

  def lid_contact(lid)
    contact = create(:contact, account: account, name: lid, identifier: lid, phone_number: nil)
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: lid)
    contact
  end

  it 'resolves the LID-only contacts of the account and reports what it found' do
    known = lid_contact('111@lid')
    unknown = lid_contact('222@lid')
    stub_request(:get, 'https://waha.test/api/u5-salao/lids/111')
      .to_return(status: 200, headers: json, body: { lid: '111@lid', pn: '5511999990000@c.us' }.to_json)
    stub_request(:get, 'https://waha.test/api/u5-salao/lids/222')
      .to_return(status: 200, headers: json, body: { lid: '222@lid', pn: nil }.to_json)
    stub_request(:get, %r{https://waha.test/api/contacts}).to_return(status: 200, headers: json, body: '{}')

    with_modified_env(WAHA_BASE_URL: 'https://waha.test', WAHA_API_KEY: 'k') do
      expect { Rake::Task['waha:resolve_lids'].invoke(account.id) }
        .to output(/1 resolved, 0 merged into an existing contact, 1 still without a number/).to_stdout
    end

    expect(known.reload).to have_attributes(phone_number: '+5511999990000', name: '+5511999990000')
    expect(unknown.reload).to have_attributes(phone_number: nil, name: 'Contact without phone number')
  end
end
