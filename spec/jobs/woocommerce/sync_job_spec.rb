require 'rails_helper'

RSpec.describe Woocommerce::SyncJob do
  let(:account) { create(:account, custom_attributes: { 'vertical_template' => 'ecommerce' }) }
  let(:connection) do
    StoreConnection.create!(account: account, store_url: 'https://loja.lizzon.com.br', consumer_key: 'ck', consumer_secret: 'cs')
  end
  let(:order) { JSON.parse(Rails.root.join('spec/fixtures/files/woocommerce/order.json').read) }
  let(:orders_url) { %r{\Ahttps://loja.lizzon.com.br/wp-json/wc/v3/orders} }

  before { allow(Resolv).to receive(:getaddress).and_return('203.0.113.10') }

  def full_page(modified: '2026-10-20T13:05:00')
    Array.new(Woocommerce::Client::PAGE_SIZE) { |i| order.merge('id' => i + 1, 'number' => (i + 1).to_s, 'date_modified_gmt' => modified) }
  end

  it 'imports the whole history one page per job and remembers when it synced', :aggregate_failures do
    stub_request(:get, orders_url).with(query: hash_including('page' => '1')).to_return(status: 200, body: full_page.to_json)
    stub_request(:get, orders_url).with(query: hash_including('page' => '2')).to_return(status: 200, body: [order.merge('id' => 999)].to_json)

    perform_enqueued_jobs { described_class.perform_later(connection.id) }

    expect(connection.store_orders.count).to eq(Woocommerce::Client::PAGE_SIZE + 1)
    expect(connection.reload.last_synced_at).to be_present
    expect(a_request(:get, orders_url).with(query: hash_including('orderby' => 'id', 'order' => 'asc'))).to have_been_made.twice
  end

  it 'asks the store only for the fields the importer reads' do
    stub_request(:get, orders_url).to_return(status: 200, body: [order].to_json)

    described_class.perform_now(connection.id)

    expect(a_request(:get, orders_url).with(query: hash_including('_fields' => Woocommerce::Client::ORDER_FIELDS))).to have_been_made
  end

  it 'stops a catch-up at the first order older than the date, newest first', :aggregate_failures do
    stub_request(:get, orders_url).to_return(status: 200, body: full_page(modified: '2026-10-18T10:00:00').to_json)

    expect { described_class.perform_now(connection.id, '2026-10-19T00:00:00Z', silent: false) }.not_to have_enqueued_job(described_class)
    expect(a_request(:get, orders_url).with(query: hash_including('orderby' => 'modified', 'order' => 'desc',
                                                                  'modified_after' => '2026-10-19T00:00:00Z'))).to have_been_made
  end

  it 'tries the same page again later while the store is down', :aggregate_failures do
    stub_request(:get, orders_url).to_return(status: 503, body: '<html>busy</html>')

    expect { described_class.perform_now(connection.id) }.to have_enqueued_job(described_class)
    expect(connection.reload.status).to eq('connected')
  end

  it 'marks the connection as failing when the store answers with an error' do
    stub_request(:get, orders_url).to_return(status: 401, body: { message: 'consumer_key inválida' }.to_json)

    described_class.perform_now(connection.id)

    expect(connection.reload).to have_attributes(status: 'failing', last_error: 'WooCommerce respondeu 401: consumer_key inválida')
  end
end
