require 'rails_helper'

RSpec.describe 'Kanban::Automations::Actions' do
  let(:account)    { create(:account) }
  let(:user)       { create(:user, account: account) }
  let(:funnel)     { create(:funnel, account: account) }
  let(:stage_a)    { create(:funnel_stage, funnel: funnel, name: 'Open') }
  let(:stage_b)    { create(:funnel_stage, funnel: funnel, name: 'Closed') }
  let(:other_funnel) { create(:funnel, account: account, name: 'Onboarding') }
  let(:other_stage)  { create(:funnel_stage, funnel: other_funnel, name: 'Day 1') }
  let(:task)       { create(:kanban_task, account: account, funnel: funnel, funnel_stage: stage_a) }

  describe Kanban::Automations::Actions::SetPriority do
    it 'updates the priority' do
      described_class.new(task: task, params: { priority: 'urgent' }).call
      expect(task.reload.priority).to eq('urgent')
    end

    it 'raises on invalid priority' do
      action = described_class.new(task: task, params: { priority: 'rofl' })
      expect { action.call }.to raise_error(Kanban::Automations::Actions::Base::ExecutionError)
    end
  end

  describe Kanban::Automations::Actions::AssignUser do
    it 'assigns valid account users' do
      described_class.new(task: task, params: { user_ids: [user.id] }).call
      expect(task.reload.assignee_ids).to contain_exactly(user.id)
    end

    it 'filters out cross-tenant ids' do
      other = create(:user)
      action = described_class.new(task: task, params: { user_ids: [other.id] })
      expect { action.call }.to raise_error(Kanban::Automations::Actions::Base::ExecutionError, /no valid user_ids/)
    end

    it 'supports append mode' do
      task.assignee_ids = [user.id]
      user2 = create(:user, account: account)
      described_class.new(task: task, params: { user_ids: [user2.id], mode: 'append' }).call
      expect(task.reload.assignee_ids).to contain_exactly(user.id, user2.id)
    end
  end

  describe Kanban::Automations::Actions::MoveToStage do
    it 'moves to the target stage' do
      described_class.new(task: task, params: { stage_id: stage_b.id }).call
      expect(task.reload.funnel_stage_id).to eq(stage_b.id)
    end

    it 'is critical and aborts on bad stage' do
      action = described_class.new(task: task, params: { stage_id: 0 })
      expect(action.critical?).to be(true)
      expect { action.call }.to raise_error(Kanban::Automations::Actions::Base::ExecutionError)
    end

    it 'no-ops when stage is already current' do
      expect { described_class.new(task: task, params: { stage_id: stage_a.id }).call }
        .not_to(change { task.reload.updated_at })
    end
  end

  describe Kanban::Automations::Actions::MoveToFunnel do
    it 'moves task to another funnel+stage on same account' do
      described_class.new(task: task, params: { funnel_id: other_funnel.id, stage_id: other_stage.id }).call
      task.reload
      expect(task.funnel_id).to eq(other_funnel.id)
      expect(task.funnel_stage_id).to eq(other_stage.id)
    end

    it 'rejects cross-tenant funnel' do
      foreign_funnel = create(:funnel)
      foreign_stage = create(:funnel_stage, funnel: foreign_funnel)
      action = described_class.new(task: task,
                                   params: { funnel_id: foreign_funnel.id, stage_id: foreign_stage.id })
      expect { action.call }.to raise_error(Kanban::Automations::Actions::Base::ExecutionError, /not on account/)
    end
  end

  describe Kanban::Automations::Actions::AddSubtask do
    it 'creates a subtask under the parent' do
      described_class.new(task: task, params: { title: 'Follow up', priority: 'high' }).call
      sub = task.subtasks.first
      expect(sub).to be_present
      expect(sub.title).to eq('Follow up')
      expect(sub.priority).to eq('high')
    end

    it 'supports placeholder rendering' do
      described_class.new(task: task, params: { title: 'Recall {{task_title}}' }).call
      expect(task.subtasks.first.title).to eq("Recall #{task.title}")
    end
  end

  describe Kanban::Automations::Actions::AddLabel do
    it 'creates a label if missing and attaches it' do
      described_class.new(task: task, params: { label: 'Urgent' }).call
      expect(task.reload.task_labels.map(&:title)).to include('urgent')
    end

    it 'is idempotent' do
      described_class.new(task: task, params: { label: 'Urgent' }).call
      described_class.new(task: task, params: { label: 'Urgent' }).call
      expect(task.reload.kanban_task_labels.count).to eq(1)
    end
  end

  describe Kanban::Automations::Actions::RemoveLabel do
    it 'detaches an existing label' do
      Kanban::Automations::Actions::AddLabel.new(task: task, params: { label: 'Hot' }).call
      described_class.new(task: task, params: { label: 'Hot' }).call
      expect(task.reload.task_labels).to be_empty
    end

    it 'is a no-op when label is absent' do
      expect { described_class.new(task: task, params: { label: 'Ghost' }).call }
        .not_to raise_error
    end
  end

  describe Kanban::Automations::Actions::SetDueDate do
    it 'sets due_date relatively via in_hours' do
      described_class.new(task: task, params: { in_hours: 24 }).call
      expect(task.reload.due_date).to be_within(1.minute).of(24.hours.from_now)
    end

    it 'supports clearing' do
      task.update!(due_date: 1.day.from_now)
      described_class.new(task: task, params: { clear: true }).call
      expect(task.reload.due_date).to be_nil
    end

    it 'raises when no params provided' do
      action = described_class.new(task: task, params: {})
      expect { action.call }.to raise_error(Kanban::Automations::Actions::Base::ExecutionError)
    end
  end

  describe Kanban::Automations::Actions::Webhook do
    it 'enqueues a delivery job for a valid url' do
      expect do
        described_class.new(task: task,
                            params: { url: 'https://example.com/hook' }).call
      end.to have_enqueued_job(Kanban::Automations::WebhookDeliveryJob)
    end

    it 'rejects non-http schemes' do
      action = described_class.new(task: task, params: { url: 'file:///etc/passwd' })
      expect { action.call }.to raise_error(Kanban::Automations::Actions::Base::ExecutionError, /must be http/)
    end

    it 'rejects unsupported methods' do
      action = described_class.new(task: task, params: { url: 'https://x.test', method: 'DELETE' })
      expect { action.call }.to raise_error(Kanban::Automations::Actions::Base::ExecutionError, /unsupported method/)
    end
  end
end
