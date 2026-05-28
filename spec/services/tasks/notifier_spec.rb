require 'rails_helper'

RSpec.describe Tasks::Notifier do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:task)    { create(:task, account: account, notify_assignees: true) }

  describe '.notify_assignment' do
    it 'creates a task_assigned Notification row' do
      expect { described_class.notify_assignment(task: task, user: user) }
        .to change { Notification.where(notification_type: 'task_assigned').count }.by(1)
    end

    it 'skips when notify_assignees is false' do
      task.update!(notify_assignees: false)
      expect { described_class.notify_assignment(task: task, user: user) }
        .not_to(change(Notification, :count))
    end

    it 'sets primary_actor to the task and user as recipient' do
      described_class.notify_assignment(task: task, user: user)
      notification = Notification.last
      expect(notification.primary_actor).to eq(task)
      expect(notification.user).to eq(user)
      expect(notification.account_id).to eq(account.id)
    end
  end

  describe '.notify_overdue' do
    it 'creates a task_overdue Notification' do
      expect { described_class.notify_overdue(task: task, user: user) }
        .to change { Notification.where(notification_type: 'task_overdue').count }.by(1)
    end
  end

  describe '.notify_commented' do
    let(:comment) { create(:task_comment, task: task, user: user) }

    it 'creates a task_commented Notification with the comment as secondary_actor' do
      described_class.notify_commented(task: task, user: user, comment: comment)
      n = Notification.where(notification_type: 'task_commented').last
      expect(n.secondary_actor).to eq(comment)
    end
  end
end
