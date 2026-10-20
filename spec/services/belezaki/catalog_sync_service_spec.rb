require 'rails_helper'

RSpec.describe Belezaki::CatalogSyncService do
  let(:account) { create(:account) }
  let(:base) { 'https://api.belezaki.com.br/api/agent/v1' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let!(:hook) do
    stub_request(:get, "#{base}/salon").to_return(status: 200, body: '{"name":"Bella"}', headers: json)
    create(:integrations_hook, :belezaki, account: account)
  end

  let(:catalog) do
    { status: 'ok',
      services: [{ 'id' => 's2', 'name' => 'Progressiva', 'active' => true, 'is_addon' => false },
                 { 'id' => 's1', 'name' => 'Corte', 'active' => true, 'is_addon' => false },
                 { 'id' => 's3', 'name' => 'Hidratação extra', 'active' => true, 'is_addon' => true }],
      professionals: [{ 'id' => 'p2', 'name' => 'Bianca', 'active' => true }, { 'id' => 'p1', 'name' => 'Ana', 'active' => true }] }
  end

  around { |example| with_modified_env(UNIVERZAP_AGENT_API_KEY: 'shared-key') { example.run } }

  def definition(key)
    account.custom_attribute_definitions.find_by(attribute_key: key, attribute_model: 'conversation_attribute')
  end

  it 'puts the salon catalogue behind the servico and profissional attributes, in alphabetical order' do
    result = described_class.new(account: account, catalog: catalog).perform

    expect(result).to eq(synced: true, services: 2, professionals: 2)
    expect(definition('servico')).to have_attributes(attribute_display_type: 'list', attribute_values: %w[Corte Progressiva])
    expect(definition('profissional')).to have_attributes(attribute_display_type: 'list', attribute_values: %w[Ana Bianca])
    expect(hook.reload.settings['catalog_synced_at']).to be_present
  end

  it 'keeps the names the template gave the attributes and only swaps the values' do
    account.custom_attribute_definitions.create!(attribute_key: 'servico', attribute_model: 'conversation_attribute',
                                                 attribute_display_name: 'Serviço', attribute_display_type: 'list',
                                                 attribute_values: %w[Corte Coloração Outro])
    account.custom_attribute_definitions.create!(attribute_key: 'profissional', attribute_model: 'conversation_attribute',
                                                 attribute_display_name: 'Profissional', attribute_display_type: 'text')

    described_class.new(account: account, catalog: catalog).perform

    expect(definition('servico')).to have_attributes(attribute_display_name: 'Serviço', attribute_values: %w[Corte Progressiva])
    expect(definition('profissional')).to have_attributes(attribute_display_name: 'Profissional', attribute_display_type: 'list',
                                                          attribute_values: %w[Ana Bianca])
  end

  it 'leaves everything alone when the catalogue did not come' do
    result = described_class.new(account: account, catalog: { status: 'unavailable', error: 'http_503' }).perform

    expect(result).to eq(synced: false)
    expect(definition('servico')).to be_nil
    expect(hook.reload.settings).not_to have_key('catalog_synced_at')
  end
end
