require 'rails_helper'

RSpec.describe Tasks::RecurrenceSchedulerJob, type: :job do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }

  it 'spawns the next occurrence for tasks past next_occurrence_at' do
    parent = create(:task, account: account, created_by_user: user,
                           recurrence_rule: { 'type' => 'daily' },
                           next_occurrence_at: 1.hour.ago)
    expect do
      described_class.perform_now
    end.to change { Task.where(recurrence_parent_id: parent.id).count }.by(1)
  end

  it 'skips tasks without a rule' do
    create(:task, account: account, created_by_user: user,
                  next_occurrence_at: 1.hour.ago)
    expect { described_class.perform_now }.not_to(change(Task, :count))
  end

  it 'swallows errors from individual rows' do
    parent = create(:task, account: account, created_by_user: user,
                           recurrence_rule: { 'type' => 'daily' },
                           next_occurrence_at: 1.hour.ago)
    allow(Tasks::RecurrenceGenerator).to receive(:spawn_next!).with(parent).and_raise('boom')
    expect { described_class.perform_now }.not_to raise_error
  end
end
