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
    let!(:other_event) { create(:kanban_webhook_subscription, account: account, events: ['task.deleted']) }
    let!(:inactive) { create(:kanban_webhook_subscription, account: account, events: ['task.created'], active: false) }

    it 'includes the wildcard subscriber' do
      result = described_class.for_event(account_id: account.id, event: 'task.created')
      expect(result.pluck(:id)).to include(wildcard.id)
    end

    it 'includes the specific subscriber' do
      result = described_class.for_event(account_id: account.id, event: 'task.created')
      expect(result.pluck(:id)).to include(specific.id)
    end

    it 'excludes subscribers listening to a different event' do
      result = described_class.for_event(account_id: account.id, event: 'task.created')
      expect(result.pluck(:id)).not_to include(other_event.id)
    end

    it 'excludes inactive subscribers' do
      result = described_class.for_event(account_id: account.id, event: 'task.created')
      expect(result.pluck(:id)).not_to include(inactive.id)
    end
  end
end
