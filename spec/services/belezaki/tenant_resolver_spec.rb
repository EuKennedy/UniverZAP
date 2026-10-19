require 'rails_helper'

RSpec.describe Belezaki::TenantResolver do
  let(:account) { create(:account) }
  let(:base) { 'https://api.belezaki.com.br/api/agent/v1' }

  around { |example| with_modified_env(UNIVERZAP_AGENT_API_KEY: 'shared-key') { example.run } }

  before do
    stub_request(:get, "#{base}/salon").to_return(status: 200, body: '{"name":"Bella"}',
                                                  headers: { 'Content-Type' => 'application/json' })
  end

  it 'prefers the salon connected in Apps over the one stamped by the login bridge' do
    create(:integrations_hook, :belezaki, account: account, settings: { external_id: 'ext-hook' })
    allow(Ai::Belezaki::TenantResolver).to receive(:external_id).and_return('ext-bridge')

    expect(described_class.external_id(account)).to eq('ext-hook')
  end

  it 'falls back to the id the login bridge stamped on the owner' do
    allow(Ai::Belezaki::TenantResolver).to receive(:external_id).with(account).and_return('ext-bridge')

    expect(described_class.external_id(account)).to eq('ext-bridge')
  end

  it 'ignores a disabled hook' do
    create(:integrations_hook, :belezaki, account: account).update!(status: 'disabled')
    allow(Ai::Belezaki::TenantResolver).to receive(:external_id).and_return(nil)

    expect(described_class.external_id(account)).to be_nil
  end
end
