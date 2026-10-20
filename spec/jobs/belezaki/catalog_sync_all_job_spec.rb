require 'rails_helper'

RSpec.describe Belezaki::CatalogSyncAllJob do
  let(:base) { 'https://api.belezaki.com.br/api/agent/v1' }

  around { |example| with_modified_env(UNIVERZAP_AGENT_API_KEY: 'shared-key') { example.run } }

  before do
    stub_request(:get, "#{base}/salon").to_return(status: 200, body: '{"name":"Bella"}',
                                                  headers: { 'Content-Type' => 'application/json' })
  end

  it 'queues one sync per account with the belezaki app connected' do
    linked = create(:integrations_hook, :belezaki).account
    create(:integrations_hook, :belezaki).update!(status: 'disabled')
    create(:account)

    expect { described_class.perform_now }.to have_enqueued_job(Belezaki::CatalogSyncJob).with(linked.id).exactly(:once)
  end
end
