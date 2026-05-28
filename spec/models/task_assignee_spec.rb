require 'rails_helper'

RSpec.describe TaskAssignee, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:task) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    subject { build(:task_assignee) }

    it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:task_id) }
  end

  describe 'callbacks' do
    let(:account) { create(:account) }
    let(:task) { create(:task, account: account, notify_assignees: true) }
    let(:user) { create(:user, account: account) }

    it 'creates an assignment activity' do
      expect { task.task_assignees.create!(user: user) }
        .to change { task.task_activities.where(action: 'assigned').count }.by(1)
    end

    it 'sends an assignment notification when notify_assignees is on' do
      allow(Tasks::Notifier).to receive(:notify_assignment)
      task.task_assignees.create!(user: user)
      expect(Tasks::Notifier).to have_received(:notify_assignment).with(task: task, user: user)
    end

    it 'broadcasts an assigned_to_you event to the user stream' do
      allow(Tasks::Broadcaster).to receive(:broadcast)
      task.task_assignees.create!(user: user)
      expect(Tasks::Broadcaster).to have_received(:broadcast)
        .with('task.assigned_to_you', task, target: :user, user: user)
    end
  end
end
