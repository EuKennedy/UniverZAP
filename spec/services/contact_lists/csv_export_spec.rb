require 'rails_helper'

RSpec.describe ContactLists::CsvExport do
  let(:account) { create(:account) }
  let(:list) { create(:contact_list, account: account, source: 'csv') }

  it 'exporta situação e consentimento de cada membro' do
    cold = create(:contact, account: account, name: 'Fria', phone_number: '+5531988881111', custom_attributes: { 'consentimento_disparo' => false })
    create(:contact_list_member, contact_list: list, contact: cold)
    create(:contact_list_member, contact_list: list, contact: nil, wa_id: '9@lid', display_name: 'Sem número', status: :left)

    rows = CSV.parse(described_class.new(list).to_csv)

    expect(rows.first).to eq(I18n.t('contact_lists.export.headers'))
    expect(rows[1]).to include('Fria', '+5531988881111', 'Active', 'Never talked to the business')
    expect(rows[2]).to include('Sem número', 'no phone', 'Left the group')
  end
end
