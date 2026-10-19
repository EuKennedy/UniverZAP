require 'rails_helper'

# Connecting the belezaki app IS the connection test: the hook only saves once
# the salon answered for the id the admin typed.
RSpec.describe Integrations::Hook, '#valid?' do
  let(:account) { create(:account) }
  let(:base) { 'https://api.belezaki.com.br/api/agent/v1' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  around { |example| with_modified_env(UNIVERZAP_AGENT_API_KEY: 'shared-key') { example.run } }

  it 'probes the salon on connect and keeps its name and timezone' do
    stub_request(:get, "#{base}/salon")
      .with(headers: { 'X-Tenant-External-Id' => 'ext-1', 'X-Univerzap-Agent-Key' => 'shared-key' })
      .to_return(status: 200, body: '{"name":"Bella","timezone":"America/Bahia"}', headers: json)

    hook = create(:integrations_hook, :belezaki, account: account)

    expect(hook.settings).to eq('external_id' => 'ext-1', 'salon_name' => 'Bella', 'timezone' => 'America/Bahia')
  end

  it 'refuses an id the salon does not recognise' do
    stub_request(:get, "#{base}/salon")
      .to_return(status: 404, body: '{"message":"Salão não encontrado.","error":"Not Found","statusCode":404}', headers: json)

    hook = build(:integrations_hook, :belezaki, account: account)

    expect(hook).not_to be_valid
    expect(hook.errors[:base]).to eq([I18n.t('belezaki.connect.not_found')])
  end

  it 'refuses to connect while the server has no shared key, without calling out' do
    with_modified_env(UNIVERZAP_AGENT_API_KEY: nil) do
      hook = build(:integrations_hook, :belezaki, account: account)

      expect(hook).not_to be_valid
      expect(hook.errors[:base]).to eq([I18n.t('belezaki.connect.not_configured')])
    end
    expect(a_request(:get, "#{base}/salon")).not_to have_been_made
  end

  it 'does not probe again when the hook is updated' do
    stub_request(:get, "#{base}/salon").to_return(status: 200, body: '{"name":"Bella"}', headers: json)
    hook = create(:integrations_hook, :belezaki, account: account)
    WebMock.reset!

    expect { hook.update!(status: 'disabled') }.not_to raise_error
  end
end
