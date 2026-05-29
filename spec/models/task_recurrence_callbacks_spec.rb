require 'rails_helper'

RSpec.describe Task, type: :model do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }

  describe 'after_update_commit :spawn_next_recurrence_on_completion' do
    it 'spawns the next occurrence when a recurring task is marked done' do
      parent = create(:task, account: account, created_by_user: user,
                             recurrence_rule: { 'type' => 'daily' },
                             due_date: 1.day.ago)
      expect do
        parent.update!(status: :done, completed_at: Time.current)
      end.to change { described_class.where(recurrence_parent_id: parent.id).count }.by(1)
    end

    it 'does not spawn when the rule is empty' do
      task = create(:task, account: account, created_by_user: user)
      expect do
        task.update!(status: :done, completed_at: Time.current)
      end.not_to(change(described_class, :count))
    end

    it 'does not double-spawn when status flips back to done after being open' do
      parent = create(:task, account: account, created_by_user: user,
                             recurrence_rule: { 'type' => 'daily' })
      parent.update!(status: :done, completed_at: Time.current)
      first_child_count = described_class.where(recurrence_parent_id: parent.id).count
      parent.update!(title: 'unrelated change')
      expect(described_class.where(recurrence_parent_id: parent.id).count).to eq(first_child_count)
    end

    it 'skips when status transitions to cancelled' do
      parent = create(:task, account: account, created_by_user: user,
                             recurrence_rule: { 'type' => 'daily' })
      expect do
        parent.update!(status: :cancelled)
      end.not_to(change { described_class.where(recurrence_parent_id: parent.id).count })
    end
  end

  describe '#recurring?' do
    it 'is true when a rule is configured' do
      task = build(:task, recurrence_rule: { 'type' => 'daily' })
      expect(task.recurring?).to be(true)
    end

    it 'is false on an empty rule' do
      task = build(:task, recurrence_rule: {})
      expect(task.recurring?).to be(false)
    end
  end
end
