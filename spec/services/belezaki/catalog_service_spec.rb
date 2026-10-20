require 'rails_helper'

RSpec.describe Belezaki::CatalogService do
  subject(:catalog) { described_class.new(account: account).perform }

  let(:account) { create(:account) }
  let(:base) { 'https://api.belezaki.com.br/api/agent/v1' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  around { |example| with_modified_env(UNIVERZAP_AGENT_API_KEY: 'shared-key') { example.run } }

  before do
    stub_request(:get, "#{base}/salon")
      .to_return(status: 200, body: '{"name":"Bella","timezone":"America/Sao_Paulo"}', headers: json)
  end

  it 'says so when the account is not linked, without calling belezaki' do
    expect(catalog).to eq(status: 'not_linked')
    expect(a_request(:get, /services|professionals/)).not_to have_been_made
  end

  context 'when the account is linked' do
    before { create(:integrations_hook, :belezaki, account: account) }

    it 'brings services and professionals as the salon answers them, plus the salon block' do
      stub_request(:get, "#{base}/services")
        .with(headers: { 'X-Tenant-External-Id' => 'ext-1' })
        .to_return(status: 200, body: { services: [{ id: 's1', name: 'Corte', price_cents: 9000 }] }.to_json, headers: json)
      stub_request(:get, "#{base}/professionals")
        .to_return(status: 200, body: { professionals: [{ id: 'p1', name: 'Ana', services: [] }] }.to_json, headers: json)

      expect(catalog).to include(status: 'ok', salon: { name: 'Bella', timezone: 'America/Sao_Paulo' })
      expect(catalog[:services].pluck('name')).to eq(%w[Corte])
      expect(catalog[:professionals].pluck('name')).to eq(%w[Ana])
      expect(catalog[:fetched_at]).to be_present
    end

    it 'reports the salon being unreachable instead of raising' do
      stub_request(:get, "#{base}/services").to_return(status: 503, body: '{"message":"down"}', headers: json)

      expect(catalog).to eq(status: 'unavailable', error: 'http_503')
    end
  end
end
