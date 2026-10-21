require 'rails_helper'

RSpec.describe ContactLists::DeduplicateService do
  let(:account) { create(:account) }
  let(:list) { create(:contact_list, account: account, source: 'csv') }

  it 'deixa uma vez só a pessoa gravada com e sem o nono dígito' do
    first = create(:contact, account: account, phone_number: '+553188881111')
    second = create(:contact, account: account, phone_number: '+5531988881111')
    [first, second].each { |contact| create(:contact_list_member, contact_list: list, contact: contact) }

    expect(described_class.new(list).perform).to eq(1)
    expect(list.members.pluck(:contact_id)).to eq([first.id])
  end
end
