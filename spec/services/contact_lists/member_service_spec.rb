require 'rails_helper'

RSpec.describe ContactLists::MemberService do
  let(:account) { create(:account) }
  let(:list) { create(:contact_list, account: account) }
  let(:service) { described_class.new(list) }
  let!(:ana) { create(:contact, account: account) }
  let!(:bia) { create(:contact, account: account) }

  it 'adiciona, conta e não duplica' do
    expect(service.add([ana.id, bia.id])).to eq(2)
    expect(service.add([ana.id])).to eq(0)
    expect(list.reload.members_count).to eq(2)
  end

  it 'ignora contato de outra conta' do
    stranger = create(:contact)

    expect(service.add([stranger.id])).to eq(0)
    expect(list.members).to be_empty
  end

  it 'reativa quem tinha saído' do
    create(:contact_list_member, contact_list: list, contact: ana, status: :left, left_at: 1.day.ago)

    expect(service.add([ana.id])).to eq(1)
    expect(list.members.find_by(contact: ana)).to have_attributes(status: 'active', left_at: nil)
  end

  it 'remove e atualiza a contagem' do
    service.add([ana.id, bia.id])

    expect(service.remove([ana.id])).to eq(1)
    expect(list.reload.members_count).to eq(1)
  end
end
