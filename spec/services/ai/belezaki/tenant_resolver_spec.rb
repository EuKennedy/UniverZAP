require 'rails_helper'

RSpec.describe Ai::Belezaki::TenantResolver do
  let(:account) { create(:account) }
  let(:cache_key) { described_class.cache_key(account.id) }

  after { Redis::Alfred.delete(cache_key) }

  describe '.external_id' do
    it 'resolves once and serves subsequent calls from the Redis cache' do
      allow(described_class).to receive(:resolve_external_id).and_return('salon-123')

      expect(described_class.external_id(account)).to eq('salon-123')
      expect(described_class.external_id(account)).to eq('salon-123')
      expect(described_class).to have_received(:resolve_external_id).once
    end

    it 'negative-caches a missing salon so repeat calls skip the DB lookup' do
      allow(described_class).to receive(:resolve_external_id).and_return(nil)

      expect(described_class.external_id(account)).to be_nil
      expect(described_class.external_id(account)).to be_nil
      expect(described_class).to have_received(:resolve_external_id).once
      expect(Redis::Alfred.get(cache_key)).to eq(described_class::NO_EXTERNAL_ID)
    end

    it 'returns nil for a blank account without resolving or caching' do
      expect(described_class).not_to receive(:resolve_external_id)

      expect(described_class.external_id(nil)).to be_nil
    end
  end

  describe '.from_subscription (deterministic salon binding)' do
    let(:user) { create(:user, account: account) }

    def subscription(external_id, status:, created_at:)
      UnivercartSubscription.create!(
        external_user_id: external_id, email: "#{external_id}@ex.com", name: 'Buyer',
        role: 'admin', status: status, user: user, created_at: created_at
      )
    end

    it 'binds the newest ACTIVE subscription when an admin maps to several' do
      subscription('salon-old', status: 'active', created_at: 3.days.ago)
      subscription('salon-new', status: 'active', created_at: 1.hour.ago)

      expect(described_class.from_subscription([user.id])).to eq('salon-new')
    end

    it 'never binds a non-active subscription' do
      subscription('salon-cancelled', status: 'cancelled', created_at: 1.hour.ago)

      expect(described_class.from_subscription([user.id])).to be_nil
    end
  end
end
