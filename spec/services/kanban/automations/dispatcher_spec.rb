require 'rails_helper'

RSpec.describe Kanban::Automations::Dispatcher do
  let(:account)    { create(:account) }
  let(:funnel)     { create(:funnel, account: account) }
  let(:other_fun)  { create(:funnel, account: account) }
  let(:stage)      { create(:funnel_stage, funnel: funnel) }
  let(:task)       { create(:kanban_task, account: account, funnel: funnel, funnel_stage: stage) }

  describe '.dispatch' do
    it 'enqueues a RunJob for every matching active rule' do
      r1 = create(:kanban_automation, account: account, funnel: funnel, event_name: 'task_created', active: true)
      _r2 = create(:kanban_automation, account: account, funnel: funnel, event_name: 'task_created', active: false)
      _r3 = create(:kanban_automation, account: account, funnel: other_fun, event_name: 'task_created', active: true)

      expect do
        described_class.dispatch(:task_created, task)
      end.to have_enqueued_job(Kanban::Automations::RunJob).with(r1.id, task.id, {})
    end

    it 'matches account-wide rules (funnel_id nil)' do
      r = create(:kanban_automation, account: account, funnel: nil, event_name: 'task_created', active: true)
      expect do
        described_class.dispatch(:task_created, task)
      end.to have_enqueued_job(Kanban::Automations::RunJob).with(r.id, task.id, {})
    end

    it 'never crosses tenant boundary' do
      foreign_account = create(:account)
      foreign_funnel  = create(:funnel, account: foreign_account)
      create(:kanban_automation, account: foreign_account, funnel: foreign_funnel,
                                 event_name: 'task_created', active: true)

      expect do
        described_class.dispatch(:task_created, task)
      end.not_to have_enqueued_job(Kanban::Automations::RunJob)
    end

    it 'silently ignores unknown events' do
      expect do
        described_class.dispatch(:nope, task)
      end.not_to have_enqueued_job(Kanban::Automations::RunJob)
    end

    it 'serialises event_payload with string keys for Sidekiq' do
      rule = create(:kanban_automation, account: account, funnel: funnel, event_name: 'task_moved_to_stage')
      expect do
        described_class.dispatch(:task_moved_to_stage, task, from_stage_id: 1, to_stage_id: 2)
      end.to have_enqueued_job(Kanban::Automations::RunJob).with(
        rule.id, task.id, { 'from_stage_id' => 1, 'to_stage_id' => 2 }
      )
    end
  end
end
