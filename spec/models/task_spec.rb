require 'rails_helper'

RSpec.describe Task, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by_user).class_name('User') }
    it { is_expected.to have_many(:task_assignees).dependent(:destroy) }
    it { is_expected.to have_many(:assignees).through(:task_assignees) }
    it { is_expected.to have_many(:task_comments).dependent(:destroy) }
    it { is_expected.to have_many(:task_activities).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:task) }

    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_most(255) }
  end

  describe 'enums' do
    it 'defines status keys' do
      expect(described_class.statuses.keys).to match_array(%w[open in_progress blocked done cancelled])
    end

    it 'defines urgency keys' do
      expect(described_class.urgencies.keys).to match_array(%w[none low medium high urgent])
    end
  end

  describe 'display_id' do
    let(:account) { create(:account) }

    it 'auto-increments per account' do
      first  = create(:task, account: account)
      second = create(:task, account: account)
      expect(second.display_id).to eq(first.display_id + 1)
    end

    it 'is independent across accounts' do
      a1 = create(:task, account: create(:account))
      a2 = create(:task, account: create(:account))
      expect([a1.display_id, a2.display_id]).to all(eq(1))
    end

    it 'keeps an explicitly provided display_id' do
      task = create(:task, display_id: 777)
      expect(task.display_id).to eq(777)
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let!(:open_task)        { create(:task, account: account, status: :open) }
    let!(:in_progress_task) { create(:task, account: account, status: :in_progress) }
    let!(:done_task)        { create(:task, account: account, status: :done) }
    let!(:overdue_task)     { create(:task, account: account, status: :open, due_date: 2.hours.ago) }
    let!(:not_overdue_task) { create(:task, account: account, status: :open, due_date: 1.day.from_now) }
    let!(:done_overdue) { create(:task, account: account, status: :done, due_date: 2.hours.ago) }

    it 'returns active tasks' do
      expect(described_class.active).to include(open_task, in_progress_task)
      expect(described_class.active).not_to include(done_task)
    end

    it 'returns overdue tasks excluding done/cancelled' do
      expect(described_class.overdue).to include(overdue_task)
      expect(described_class.overdue).not_to include(not_overdue_task, done_overdue)
    end

    it 'scopes by assignee' do
      open_task.task_assignees.create!(user: user)
      expect(described_class.assigned_to(user.id)).to contain_exactly(open_task)
    end

    it 'scopes by creator' do
      mine = create(:task, account: account, created_by_user: user)
      expect(described_class.created_by(user.id)).to include(mine)
      expect(described_class.created_by(user.id)).not_to include(open_task)
    end
  end

  describe 'callbacks' do
    let(:account) { create(:account) }
    let(:task) { create(:task, account: account) }

    it 'logs a creation activity' do
      expect(task.task_activities.where(action: 'created').count).to eq(1)
    end

    it 'logs status changes' do
      task.update!(status: :in_progress)
      expect(task.task_activities.where(action: 'status_changed')).to exist
    end

    it 'broadcasts on create' do
      allow(Tasks::Broadcaster).to receive(:broadcast)
      created = create(:task, account: account)
      expect(Tasks::Broadcaster).to have_received(:broadcast)
        .with('task.created', created, target: :account)
    end
  end

  describe '#push_event_data' do
    let(:task) { create(:task) }

    it 'returns full payload with associations summary' do
      payload = task.push_event_data
      expect(payload).to include(:id, :display_id, :title, :status, :urgency, :assignees,
                                 :comments_count, :activities_count, :created_at, :updated_at)
    end
  end
end
