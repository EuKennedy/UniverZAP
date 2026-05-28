require 'rails_helper'

RSpec.describe TaskComment, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:task) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'callbacks' do
    let(:account) { create(:account) }
    let(:task) { create(:task, account: account) }
    let(:user) { create(:user, account: account) }

    it 'logs a comment_added activity' do
      expect { create(:task_comment, task: task, user: user) }
        .to change { task.task_activities.where(action: 'comment_added').count }.by(1)
    end

    it 'broadcasts a comment_added event' do
      allow(Tasks::Broadcaster).to receive(:broadcast)
      create(:task_comment, task: task, user: user)
      expect(Tasks::Broadcaster).to have_received(:broadcast)
        .with('task.comment_added', task, target: :account, payload: kind_of(Hash))
    end
  end
end
