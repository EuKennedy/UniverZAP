require 'rails_helper'

RSpec.describe KanbanApiToken, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by_user).optional }
  end

  describe '.generate!' do
    let(:account) { create(:account) }

    it 'returns a token with prefix + digest, exposes raw once' do
      token = described_class.generate!(account: account, name: 'CI', scopes: ['read:tasks'])
      expect(token.raw_token).to start_with('zk_live_')
      expect(token.token_prefix).to eq(token.raw_token[0, 16])
      expect(token.token_digest).to eq(Digest::SHA256.hexdigest(token.raw_token))
    end

    it 'rejects unknown scopes' do
      expect do
        described_class.generate!(account: account, name: 'x', scopes: ['launch:missiles'])
      end.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '.authenticate' do
    let(:account) { create(:account) }
    let!(:token)  { described_class.generate!(account: account, name: 'CI', scopes: ['read:tasks']) }

    it 'returns the token for a valid raw value' do
      expect(described_class.authenticate(token.raw_token)).to eq(token)
    end

    it 'returns nil for a wrong value' do
      expect(described_class.authenticate('zk_live_garbage')).to be_nil
    end

    it 'returns nil for a value without the zk_live_ prefix' do
      expect(described_class.authenticate('Bearer wrong')).to be_nil
    end

    it 'returns nil for revoked tokens' do
      token.revoke!
      expect(described_class.authenticate(token.raw_token)).to be_nil
    end

    it 'returns nil for expired tokens' do
      token.update!(expires_at: 1.minute.ago)
      expect(described_class.authenticate(token.raw_token)).to be_nil
    end
  end

  describe '#has_scope?' do
    it 'reflects the granted scopes' do
      t = build(:kanban_api_token, scopes: ['read:tasks', 'write:tasks'])
      expect(t.has_scope?('read:tasks')).to be true
      expect(t.has_scope?('manage:automations')).to be false
    end
  end
end
