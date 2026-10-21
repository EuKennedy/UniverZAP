require 'rails_helper'

RSpec.describe ContactLists::CsvImportService do
  let(:account) { create(:account) }
  let(:list) { create(:contact_list, account: account, source: 'csv') }

  it 'lê nome e telefone em qualquer ordem, com ponto e vírgula e cabeçalho' do
    content = "Nome;Telefone\nAna Lima;(31) 98888-1111\n31988882222;Bia\nqualquer coisa;123\n"

    result = described_class.new(list, content).perform

    expect(result).to include('rows' => 3, 'added' => 2, 'created' => 2, 'invalid' => 1)
    expect(account.contacts.find_by(phone_number: '+5531988881111').name).to eq('Ana Lima')
    expect(list.reload.members_count).to eq(2)
  end

  it 'não duplica contato existente e só marca frio quem foi criado' do
    old = create(:contact, account: account, phone_number: '+553188881111')

    described_class.new(list, "31988881111\n31977770000\n", cold: true).perform

    expect(list.members.pluck(:contact_id)).to include(old.id)
    expect(old.reload.custom_attributes).not_to have_key('consentimento_disparo')
    expect(account.contacts.find_by(phone_number: '+5531977770000').custom_attributes['consentimento_disparo']).to be(false)
  end
end
