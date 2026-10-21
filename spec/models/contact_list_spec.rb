require 'rails_helper'

RSpec.describe ContactList do
  let(:account) { create(:account) }

  it 'exige o grupo quando a origem é grupo' do
    list = build(:contact_list, account: account, source: 'group', group_identifier: nil)

    expect(list).not_to be_valid
    expect(list.errors[:group_identifier]).to be_present
  end

  it 'recusa origem desconhecida' do
    expect(build(:contact_list, account: account, source: 'planilha')).not_to be_valid
  end

  it 'só considera disparáveis os ativos com telefone' do
    list = create(:contact_list, account: account)
    with_phone = create(:contact, account: account, phone_number: '+5531988880001')
    without_phone = create(:contact, account: account)
    gone = create(:contact, account: account, phone_number: '+5531988880002')
    create(:contact_list_member, contact_list: list, contact: with_phone)
    create(:contact_list_member, contact_list: list, contact: without_phone)
    create(:contact_list_member, contact_list: list, contact: gone, status: :left)
    create(:contact_list_member, contact_list: list, contact: nil, wa_id: '123@lid')

    expect(list.sendable_contact_ids).to eq([with_phone.id])
  end

  it 'não repete o mesmo contato na lista' do
    list = create(:contact_list, account: account)
    contact = create(:contact, account: account)
    create(:contact_list_member, contact_list: list, contact: contact)

    expect(build(:contact_list_member, contact_list: list, contact: contact)).not_to be_valid
  end

  it 'leva as listas junto quando o contato é mesclado' do
    list = create(:contact_list, account: account)
    base = create(:contact, account: account, phone_number: '+5531988880003')
    mergee = create(:contact, account: account, identifier: '99@lid')
    create(:contact_list_member, contact_list: list, contact: mergee)

    ContactMergeAction.new(account: account, base_contact: base, mergee_contact: mergee).perform

    expect(list.members.pluck(:contact_id)).to eq([base.id])
  end
end
