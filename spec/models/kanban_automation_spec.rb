require 'rails_helper'

RSpec.describe KanbanAutomation, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:funnel).optional }
  end

  describe 'validations' do
    subject { build(:kanban_automation) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(120) }
    it { is_expected.to validate_inclusion_of(:event_name).in_array(described_class::EVENTS) }

    it 'rejects an unknown event_name' do
      automation = build(:kanban_automation, event_name: 'invalid_event')
      expect(automation).not_to be_valid
    end

    it 'rejects when funnel belongs to a different account' do
      other_account = create(:account)
      other_funnel = create(:funnel, account: other_account)
      automation = build(:kanban_automation, funnel: other_funnel)
      expect(automation).not_to be_valid
      expect(automation.errors[:funnel]).to include('must belong to the same account')
    end

    it 'allows an account-wide rule with funnel_id=nil' do
      automation = build(:kanban_automation, funnel: nil)
      expect(automation).to be_valid
    end

    it 'rejects more than MAX_ACTIONS actions' do
      automation = build(:kanban_automation,
                         actions: Array.new(described_class::MAX_ACTIONS + 1) do
                           { 'type' => 'set_priority', 'params' => { 'priority' => 'high' } }
                         end)
      expect(automation).not_to be_valid
      expect(automation.errors[:actions].join).to include('max')
    end

    it 'rejects an action with unknown type' do
      automation = build(:kanban_automation,
                         actions: [{ 'type' => 'launch_missiles', 'params' => {} }])
      expect(automation).not_to be_valid
      expect(automation.errors[:actions].join).to include('unknown type')
    end

    it 'rejects conditions with unsupported value types' do
      automation = build(:kanban_automation, conditions: { 'priority_in' => { nested: 'no' } })
      expect(automation).not_to be_valid
      expect(automation.errors[:conditions].join).to include('unsupported value type')
    end
  end

  describe '#record_run!' do
    let(:automation) { create(:kanban_automation) }

    it 'increments run_count and stamps last_run_at' do
      expect { automation.record_run! }.to change(automation, :run_count).by(1)
      expect(automation.last_run_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe '#record_error!' do
    let(:automation) { create(:kanban_automation) }

    it 'truncates the error message to 500 chars' do
      automation.record_error!('e' * 1000)
      expect(automation.reload.last_error_message.length).to eq(500)
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let!(:active_created)   { create(:kanban_automation, account: account, event_name: 'task_created', active: true) }
    let!(:inactive_created) { create(:kanban_automation, account: account, event_name: 'task_created', active: false) }
    let!(:moved)            { create(:kanban_automation, account: account, event_name: 'task_moved_to_stage', active: true) }
    let!(:other_account)    { create(:kanban_automation, event_name: 'task_created', active: true) }

    it 'scopes active rules' do
      expect(described_class.active).to include(active_created, moved, other_account)
      expect(described_class.active).not_to include(inactive_created)
    end

    it 'scopes by event' do
      expect(described_class.for_event('task_created')).to contain_exactly(active_created, inactive_created, other_account)
    end

    it 'scopes by account' do
      expect(described_class.for_account(account.id)).to contain_exactly(active_created, inactive_created, moved)
    end
  end
end
