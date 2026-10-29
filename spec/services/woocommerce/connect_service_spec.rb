require 'rails_helper'

RSpec.describe Woocommerce::ConnectService do
  let(:account) { create(:account, custom_attributes: { 'vertical_template' => 'ecommerce' }) }
  let(:store) { 'https://loja.lizzon.com.br' }
  let(:api) { "#{store}/wp-json/wc/v3" }

  before do
    allow(Resolv).to receive(:getaddress).and_return('203.0.113.10')
    stub_request(:get, %r{\A#{api}/orders}).to_return(status: 200, body: '[]', headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, %r{\A#{api}/webhooks})
      .to_return({ status: 201, body: { id: 11 }.to_json }, { status: 201, body: { id: 12 }.to_json })
  end

  def connect
    described_class.new(account).connect(store_url: "#{store}/", consumer_key: 'ck_live', consumer_secret: 'cs_live')
  end

  it 'probes the keys, saves them and registers the order webhooks', :aggregate_failures do
    connection = connect

    expect(connection).to have_attributes(store_url: store, consumer_key: 'ck_live', status: 'connected', webhook_ids: [11, 12])
    expect(a_request(:post, %r{\A#{api}/webhooks}).with { |req| JSON.parse(req.body)['topic'] == 'order.created' }).to have_been_made
    expect(a_request(:post, %r{\A#{api}/webhooks}).with do |req|
      JSON.parse(req.body).values_at('delivery_url', 'secret') == [connection.webhook_url, connection.webhook_secret]
    end).to have_been_made.twice
  end

  it 'imports the whole order history in the background' do
    expect { connect }.to have_enqueued_job(Woocommerce::SyncJob).with(kind_of(Integer))
  end

  describe '#ensure_webhooks' do
    before { connect }

    it 'switches back on a webhook the store turned off' do
      stub_request(:get, %r{\A#{api}/webhooks/11}).to_return(status: 200, body: { id: 11, status: 'active' }.to_json)
      stub_request(:get, %r{\A#{api}/webhooks/12}).to_return(status: 200, body: { id: 12, status: 'disabled' }.to_json)
      stub_request(:put, %r{\A#{api}/webhooks/12}).to_return(status: 200, body: { id: 12, status: 'active' }.to_json)

      described_class.new(account).ensure_webhooks

      expect(a_request(:put, %r{\A#{api}/webhooks/12}).with { |req| JSON.parse(req.body)['status'] == 'active' }).to have_been_made
    end

    it 'registers the webhooks again when one is gone' do
      stub_request(:get, %r{\A#{api}/webhooks/11}).to_return(status: 404, body: { message: 'ID inválido' }.to_json)
      stub_request(:delete, %r{\A#{api}/webhooks/1[12]}).to_return(status: 200, body: '{}')
      stub_request(:post, %r{\A#{api}/webhooks})
        .to_return({ status: 201, body: { id: 21 }.to_json }, { status: 201, body: { id: 22 }.to_json })

      described_class.new(account).ensure_webhooks

      expect(account.store_connection.reload.webhook_ids).to eq([21, 22])
    end
  end

  it 'sends the keys as query parameters, which WordPress hosts do not strip' do
    connect

    expect(a_request(:get, %r{\A#{api}/orders}).with(query: hash_including('consumer_key' => 'ck_live', 'consumer_secret' => 'cs_live')))
      .to have_been_made
  end

  it 'saves nothing when the store refuses the keys' do
    stub_request(:get, %r{\A#{api}/orders}).to_return(status: 401, body: { message: 'Chave inválida' }.to_json)

    expect { connect }.to raise_error(Woocommerce::Client::Error, /401: Chave inválida/)
    expect(account.reload.store_connection).to be_nil
  end

  it 'refuses a store that resolves to a private address' do
    allow(Resolv).to receive(:getaddress).and_return('10.0.0.5')

    expect { connect }.to raise_error(Woocommerce::Client::Error, /não permitido/)
  end

  it 'refuses plain http' do
    expect do
      described_class.new(account).connect(store_url: 'http://loja.lizzon.com.br', consumer_key: 'ck', consumer_secret: 'cs')
    end.to raise_error(Woocommerce::Client::Error, /https/)
  end

  it 'removes the webhooks from the store when disconnecting' do
    connect
    stub_request(:delete, %r{\A#{api}/webhooks/1[12]}).to_return(status: 200, body: '{}')

    described_class.new(account).disconnect

    expect(a_request(:delete, %r{\A#{api}/webhooks/11})).to have_been_made
    expect(account.reload.store_connection).to be_nil
  end
end
