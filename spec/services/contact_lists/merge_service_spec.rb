require 'rails_helper'

RSpec.describe ContactLists::MergeService do
  let(:account) { create(:account) }
  let(:list) { create(:contact_list, account: account, source: 'csv') }

  it 'junta só os ativos numa lista nova, sem repetir ninguém' do
    ana = create(:contact, account: account, phone_number: '+5531988881111')
    bia = create(:contact, account: account, phone_number: '+5531988882222')
    gone = create(:contact, account: account, phone_number: '+5531988883333')
    other = create(:contact_list, account: account)
    [list, other].each { |each_list| create(:contact_list_member, contact_list: each_list, contact: ana) }
    create(:contact_list_member, contact_list: other, contact: bia)
    create(:contact_list_member, contact_list: other, contact: gone, status: :left)

    merged = described_class.new(account: account, list_ids: [list.id, other.id], name: 'Todas').perform

    expect(merged.contacts).to contain_exactly(ana, bia)
    expect(merged.metadata['merged_from']).to contain_exactly(list.id, other.id)
  end

  it 'pede pelo menos duas listas' do
    expect { described_class.new(account: account, list_ids: [list.id], name: 'x').perform }.to raise_error(ArgumentError)
  end
end
