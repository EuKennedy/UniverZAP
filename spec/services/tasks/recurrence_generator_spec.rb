require 'rails_helper'

RSpec.describe Tasks::RecurrenceGenerator do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }

  describe '.next_occurrence' do
    it 'returns nil for unknown rule types' do
      expect(described_class.next_occurrence({ 'type' => 'nope' })).to be_nil
    end

    it 'computes a daily rule one day ahead' do
      travel_to(Time.zone.parse('2026-05-10 12:00')) do
        result = described_class.next_occurrence({ 'type' => 'daily' })
        expect(result.to_date).to eq(Date.parse('2026-05-11'))
        expect(result.hour).to eq(9)
      end
    end

    it 'walks forward to the next matching weekday' do
      # 2026-05-10 is a Sunday (wday 0). Asking for Wednesday (wday 3)
      # should land on 2026-05-13.
      travel_to(Time.zone.parse('2026-05-10 12:00')) do
        result = described_class.next_occurrence({ 'type' => 'weekly', 'weekdays' => [3] })
        expect(result.to_date).to eq(Date.parse('2026-05-13'))
      end
    end

    it 'rolls a monthly day forward when past the current month' do
      Timecop.freeze(Time.zone.parse('2026-05-20 12:00')) do
        result = described_class.next_occurrence({ 'type' => 'monthly', 'day' => 15 })
        expect(result.to_date).to eq(Date.parse('2026-06-15'))
      end
    end

    it 'returns nil for invalid cron expressions' do
      expect(described_class.next_occurrence({ 'type' => 'cron', 'cron' => 'not-cron' })).to be_nil
    end
  end

  describe '.spawn_next!' do
    let!(:parent) do
      create(:task, account: account, created_by_user: user,
                    recurrence_rule: { 'type' => 'daily' }, due_date: 2.days.ago)
    end

    it 'creates a child Task linked to the parent' do
      expect { described_class.spawn_next!(parent) }.to change(Task, :count).by(1)
      expect(parent.recurrence_children.count).to eq(1)
    end

    it 'updates the parent next_occurrence_at' do
      described_class.spawn_next!(parent)
      expect(parent.reload.next_occurrence_at).not_to be_nil
    end

    it 'copies assignees onto the new occurrence' do
      assignee = create(:user, account: account)
      parent.task_assignees.create!(user: assignee)
      child = described_class.spawn_next!(parent)
      expect(child.assignees.pluck(:id)).to include(assignee.id)
    end
  end
end
