require 'rails_helper'

RSpec.describe Ai::CustomToolExecutor do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }

  def tool(attrs = {})
    Ai::CustomTool.create!(
      { ai_assistant: assistant, account: account, title: 'Buscar', slug: 'buscar',
        endpoint_url: 'https://loja.example.com/api', http_method: 'GET',
        auth_type: 'none', param_schema: [] }.merge(attrs)
    )
  end

  it 'exposes the Anthropic definitions of the tools it holds' do
    expect(described_class.new([tool]).definitions.first[:name]).to eq('buscar')
  end

  it 'returns error data instead of raising for an unknown tool' do
    expect(JSON.parse(described_class.new([tool]).call('inexistente', {}))).to include('error' => true)
  end

  it 'returns the endpoint response body on success' do
    allow(Resolv).to receive(:getaddress).and_return('93.184.216.34')
    stub_request(:get, 'https://loja.example.com/api').to_return(status: 200, body: '{"ok":true}')

    expect(described_class.new([tool]).call('buscar', {})).to eq('{"ok":true}')
  end

  # SSRF: even a reachable endpoint is refused when its hostname resolves to
  # private space — proven by stubbing a 200 the executor must NOT reach.
  it 'blocks a hostname that resolves to a private ip before calling it' do
    allow(Resolv).to receive(:getaddress).and_return('127.0.0.1')
    stub_request(:get, 'https://loja.example.com/api').to_return(status: 200, body: '{"ok":true}')

    expect(JSON.parse(described_class.new([tool]).call('buscar', {}))).to include('error' => true)
  end
end
