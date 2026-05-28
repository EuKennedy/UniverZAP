require 'rails_helper'

RSpec.describe Tasks::Broadcaster do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:task)    { create(:task, account: account) }

  # IMPORTANT: `let(:task) { create(:task, ...) }` triggers Task's
  # `after_create_commit :broadcast_created` callback which calls
  # `Tasks::Broadcaster.broadcast` once on its own. If we set up the
  # mock BEFORE the task is created, that callback bumps the spy count
  # to 1 before the test body even runs, producing false-positive
  # double-broadcast assertions. Touch `task` FIRST so the real path
  # runs (no-op with the test cable adapter), THEN install the spy.
  before do
    task
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe '.broadcast' do
    it 'broadcasts to the per-account stream by default' do
      described_class.broadcast('task.created', task, target: :account)
      expect(ActionCable.server).to have_received(:broadcast)
        .with("account_#{account.id}_tasks", hash_including(event: 'task.created', data: kind_of(Hash)))
    end

    it 'broadcasts to the per-user stream when target=user' do
      described_class.broadcast('task.assigned_to_you', task, target: :user, user: user)
      expect(ActionCable.server).to have_received(:broadcast)
        .with("account_#{account.id}_user_#{user.id}_tasks",
              hash_including(event: 'task.assigned_to_you'))
    end

    it 'skips broadcast when target=user and user is nil' do
      described_class.broadcast('task.assigned_to_you', task, target: :user, user: nil)
      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    it 'uses the supplied payload over the task push_event_data' do
      described_class.broadcast('task.deleted', task, target: :account, payload: { id: task.id })
      expect(ActionCable.server).to have_received(:broadcast)
        .with("account_#{account.id}_tasks",
              hash_including(event: 'task.deleted', data: { id: task.id }))
    end

    it 'rescues and logs broadcast errors' do
      allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, 'boom')
      allow(Rails.logger).to receive(:error)
      expect { described_class.broadcast('task.created', task, target: :account) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/Tasks::Broadcaster/)
    end
  end
end
