require 'rails_helper'

RSpec.describe KanbanWebhookSubscription, type: :model do
  describe 'validations' do
    subject { build(:kanban_webhook_subscription) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:url) }

    it 'rejects non-http(s) urls' do
      sub = build(:kanban_webhook_subscription, url: 'file:///etc/passwd')
      expect(sub).not_to be_valid
    end

    it 'rejects unknown events' do
      sub = build(:kanban_webhook_subscription, events: ['task.created', 'launch.missiles'])
      expect(sub).not_to be_valid
    end

    it 'accepts the empty events array as wildcard' do
      sub = build(:kanban_webhook_subscription, events: [])
      expect(sub).to be_valid
    end
  end

  describe 'defaults' do
    it 'assigns a 64-char hex secret on create when not provided' do
      sub = described_class.create!(account: create(:account), name: 'CI', url: 'https://x.test', events: [], secret: nil)
      expect(sub.secret.length).to eq(64)
    end
  end

  describe '.for_event' do
    let(:account) { create(:account) }
    let!(:wildcard) { create(:kanban_webhook_subscription, account: account, events: []) }
    let!(:specific) { create(:kanban_webhook_subscription, account: account, events: ['task.created']) }

    before do
      # Decoy subscriptions — must NOT be returned for `task.created`.
      create(:kanban_webhook_subscription, account: account, events: ['task.deleted'])
      create(:kanban_webhook_subscription, account: account, events: ['task.created'], active: false)
    end

    it 'returns wildcard + specific subscribers for the event' do
      result = described_class.for_event(account_id: account.id, event: 'task.created')
      expect(result).to contain_exactly(wildcard, specific)
    end
  end
end
