require 'rails_helper'

RSpec.describe Woocommerce::SyncJob do
  let(:account) { create(:account, custom_attributes: { 'vertical_template' => 'ecommerce' }) }
  let(:connection) do
    StoreConnection.create!(account: account, store_url: 'https://loja.lizzon.com.br', consumer_key: 'ck', consumer_secret: 'cs')
  end
  let(:order) { JSON.parse(Rails.root.join('spec/fixtures/files/woocommerce/order.json').read) }
  let(:orders_url) { %r{\Ahttps://loja.lizzon.com.br/wp-json/wc/v3/orders} }

  before { allow(Resolv).to receive(:getaddress).and_return('203.0.113.10') }

  it 'imports every page and remembers when it synced', :aggregate_failures do
    page_one = Array.new(Woocommerce::Client::PAGE_SIZE) { |i| order.merge('id' => i + 1, 'number' => (i + 1).to_s) }
    stub_request(:get, orders_url).with(query: hash_including('page' => '1')).to_return(status: 200, body: page_one.to_json)
    stub_request(:get, orders_url).with(query: hash_including('page' => '2')).to_return(status: 200, body: [order.merge('id' => 999)].to_json)

    described_class.perform_now(connection.id, 90.days.ago.iso8601)

    expect(connection.store_orders.count).to eq(Woocommerce::Client::PAGE_SIZE + 1)
    expect(connection.reload.last_synced_at).to be_present
  end

  it 'marks the connection as failing when the store answers with an error' do
    stub_request(:get, orders_url).to_return(status: 401, body: { message: 'consumer_key inválida' }.to_json)

    described_class.perform_now(connection.id)

    expect(connection.reload).to have_attributes(status: 'failing', last_error: 'WooCommerce respondeu 401: consumer_key inválida')
  end
end
