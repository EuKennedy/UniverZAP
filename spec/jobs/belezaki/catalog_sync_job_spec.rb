require 'rails_helper'

RSpec.describe Belezaki::CatalogSyncJob do
  let(:account) { create(:account) }

  it 'refreshes the catalogue and syncs it into the account attributes' do
    catalog = { status: 'ok', services: [], professionals: [] }
    reader = instance_double(Belezaki::CatalogService, perform: catalog)
    syncer = instance_double(Belezaki::CatalogSyncService, perform: { synced: true })
    allow(Belezaki::CatalogService).to receive(:new).with(account: account, refresh: true).and_return(reader)
    allow(Belezaki::CatalogSyncService).to receive(:new).with(account: account, catalog: catalog).and_return(syncer)

    described_class.perform_now(account.id)

    expect(syncer).to have_received(:perform)
  end
end
