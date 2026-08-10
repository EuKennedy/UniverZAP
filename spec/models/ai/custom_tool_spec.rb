require 'rails_helper'

RSpec.describe Ai::CustomTool do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }

  def build_tool(attrs = {})
    described_class.new(
      { ai_assistant: assistant, account: account, title: 'Buscar Produto',
        endpoint_url: 'https://loja.example.com/api/products', http_method: 'GET', auth_type: 'none',
        param_schema: [{ 'name' => 'q', 'type' => 'string', 'description' => 'termo', 'required' => true }] }.merge(attrs)
    )
  end

  it 'is valid with an https endpoint and generates a slug from the title' do
    tool = build_tool
    expect(tool).to be_valid
    tool.save!
    expect(tool.slug).to eq('buscar_produto')
  end

  # The SSRF surface: only public https hostnames may be reached.
  it 'rejects non-https, IP and localhost endpoints' do
    expect(build_tool(endpoint_url: 'http://loja.example.com/api')).not_to be_valid
    expect(build_tool(endpoint_url: 'https://127.0.0.1/api')).not_to be_valid
    expect(build_tool(endpoint_url: 'https://localhost/api')).not_to be_valid
  end

  # Tenant isolation is the whole point: the slug is unique per AGENT, so the
  # same tool name never collides across agents (or leaks between them).
  it 'scopes the slug to the agent, not globally' do
    build_tool.save!
    other = create(:ai_assistant, account: account)

    expect(build_tool(ai_assistant: other)).to be_valid
  end

  it 'exposes an Anthropic tool schema built from the param schema' do
    schema = build_tool.tap(&:save!).to_tool_definition

    expect(schema[:name]).to eq('buscar_produto')
    expect(schema[:input_schema][:properties]).to eq('q' => { 'type' => 'string', 'description' => 'termo' })
    expect(schema[:input_schema][:required]).to eq(['q'])
  end

  it 'builds auth from the per-record config' do
    expect(build_tool(auth_type: 'bearer', auth_config: { 'token' => 'abc' }).build_auth_headers)
      .to eq('Authorization' => 'Bearer abc')
    expect(build_tool(auth_type: 'basic', auth_config: { 'username' => 'u', 'password' => 'p' }).build_basic_auth_credentials)
      .to eq(%w[u p])
  end

  describe '#build_request_url' do
    # The bug this covers: a GET tool pointed at a plain endpoint used to drop
    # every parameter, so a product search searched for nothing, the agent
    # "found nothing" whatever the catalogue held, and it started guessing ids.
    it 'sends the params a plain GET endpoint has no placeholder for as the query string' do
      url = build_tool.build_request_url({ 'q' => 'volume control blond' })

      expect(url).to eq('https://loja.example.com/api/products?q=volume+control+blond')
    end

    it 'keeps a query string the operator already wrote into the endpoint' do
      tool = build_tool(endpoint_url: 'https://loja.example.com/api/products?store=lizzon')

      expect(tool.build_request_url({ 'q' => 'blond' }))
        .to eq('https://loja.example.com/api/products?store=lizzon&q=blond')
    end

    # A name with spaces rendered raw produced an invalid URI, and the executor
    # turned that into a generic "could not complete this action".
    it 'url-encodes a value substituted into the path' do
      tool = build_tool(endpoint_url: 'https://loja.example.com/api/products/{{ q }}')

      expect(tool.build_request_url({ 'q' => 'volume control blond' }))
        .to eq('https://loja.example.com/api/products/volume%20control%20blond')
    end

    it 'does not repeat a param the template already consumed' do
      tool = build_tool(endpoint_url: 'https://loja.example.com/api/products/{{ id }}')

      expect(tool.build_request_url({ 'id' => '42' })).to eq('https://loja.example.com/api/products/42')
    end

    it 'appends only the leftovers when the template consumes some of the params' do
      tool = build_tool(endpoint_url: 'https://loja.example.com/api/products/{{ id }}')

      expect(tool.build_request_url({ 'id' => '42', 'expand' => 'variants' }))
        .to eq('https://loja.example.com/api/products/42?expand=variants')
    end

    # On a POST the leftovers are already the JSON body; duplicating them in the
    # query would send every field twice.
    it 'leaves a POST url alone' do
      tool = build_tool(http_method: 'POST')

      expect(tool.build_request_url({ 'q' => 'blond' })).to eq('https://loja.example.com/api/products')
    end

    it 'serialises a structured param instead of interpolating a Ruby hash' do
      url = build_tool.build_request_url({ 'items' => [{ 'id' => 1 }] })

      expect(url).to eq('https://loja.example.com/api/products?items=%5B%7B%22id%22%3A1%7D%5D')
    end
  end
end
