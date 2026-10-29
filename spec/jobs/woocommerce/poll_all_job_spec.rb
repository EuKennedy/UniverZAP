require 'rails_helper'

RSpec.describe Woocommerce::PollAllJob do
  let(:account) { create(:account, custom_attributes: { 'vertical_template' => 'ecommerce' }) }
  let!(:connection) do
    StoreConnection.create!(account: account, store_url: 'https://loja.lizzon.com.br', consumer_key: 'ck', consumer_secret: 'cs',
                            last_synced_at: 2.hours.ago)
  end
  let(:service) { instance_double(Woocommerce::ConnectService, ensure_webhooks: true) }

  before { allow(Woocommerce::ConnectService).to receive(:new).and_return(service) }

  it 'checks the webhooks and catches up only the last day', :aggregate_failures do
    described_class.perform_now

    expect(service).to have_received(:ensure_webhooks)
    expect(Woocommerce::SyncJob).to have_been_enqueued.with(connection.id, kind_of(String), silent: false)
  end

  it 'leaves alone a store still importing its history' do
    connection.update!(last_synced_at: nil)

    expect { described_class.perform_now }.not_to have_enqueued_job(Woocommerce::SyncJob)
  end

  it 'marks the store as failing when its webhooks cannot be checked' do
    allow(service).to receive(:ensure_webhooks).and_raise(Woocommerce::Client::Error, 'WooCommerce respondeu 401')

    described_class.perform_now

    expect(connection.reload).to have_attributes(status: 'failing', last_error: 'WooCommerce respondeu 401')
  end
end
