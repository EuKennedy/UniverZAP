require 'rails_helper'

RSpec.describe Tasks::OverdueScannerJob, type: :job do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }

  describe '#perform' do
    it 'notifies assignees of tasks overdue inside the lookback window' do
      overdue = create(:task, account: account, status: :open, due_date: 5.minutes.ago)
      overdue.task_assignees.create!(user: user)

      allow(Tasks::Notifier).to receive(:notify_overdue)
      described_class.new.perform
      expect(Tasks::Notifier).to have_received(:notify_overdue).with(task: overdue, user: user)
    end

    it 'skips tasks not yet due' do
      future = create(:task, account: account, status: :open, due_date: 1.day.from_now)
      future.task_assignees.create!(user: user)
      allow(Tasks::Notifier).to receive(:notify_overdue)
      described_class.new.perform
      expect(Tasks::Notifier).not_to have_received(:notify_overdue)
    end

    it 'skips done or cancelled tasks even if overdue' do
      done = create(:task, account: account, status: :done, due_date: 5.minutes.ago)
      done.task_assignees.create!(user: user)
      cancelled = create(:task, account: account, status: :cancelled, due_date: 5.minutes.ago)
      cancelled.task_assignees.create!(user: user)
      allow(Tasks::Notifier).to receive(:notify_overdue)
      described_class.new.perform
      expect(Tasks::Notifier).not_to have_received(:notify_overdue)
    end

    it 'skips tasks that crossed due_date before the lookback window' do
      old = create(:task, account: account, status: :open, due_date: 1.hour.ago)
      old.task_assignees.create!(user: user)
      allow(Tasks::Notifier).to receive(:notify_overdue)
      described_class.new.perform
      expect(Tasks::Notifier).not_to have_received(:notify_overdue)
    end
  end
end
