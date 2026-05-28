require 'rails_helper'

RSpec.describe Kanban::Automations::Executor do
  let(:account) { create(:account) }
  let(:funnel) { create(:funnel, account: account) }
  let(:stage_open) { create(:funnel_stage, funnel: funnel, name: 'Open') }
  let(:stage_won)  { create(:funnel_stage, funnel: funnel, name: 'Won', status_type: :won) }
  let(:task)       { create(:kanban_task, account: account, funnel: funnel, funnel_stage: stage_open) }

  describe '.call' do
    context 'when rule is inactive' do
      it 'returns :skipped_inactive' do
        rule = create(:kanban_automation, account: account, funnel: funnel, active: false)
        expect(described_class.call(rule: rule, task: task)).to eq(:skipped_inactive)
      end
    end

    context 'when conditions do not match' do
      it 'returns :skipped_no_match' do
        rule = create(:kanban_automation, account: account, funnel: funnel,
                                          conditions: { 'priority_in' => ['urgent'] })
        expect(described_class.call(rule: rule, task: task)).to eq(:skipped_no_match)
      end
    end

    context 'when matching conditions + valid actions' do
      it 'executes the action chain and records the run' do
        rule = create(:kanban_automation, account: account, funnel: funnel,
                                          actions: [{ 'type' => 'set_priority',
                                                      'params' => { 'priority' => 'high' } }])
        described_class.call(rule: rule, task: task)
        expect(task.reload.priority).to eq('high')
        expect(rule.reload.run_count).to eq(1)
      end
    end

    context 'when a critical action fails' do
      it 'records the error on the rule' do
        rule = create(:kanban_automation, account: account, funnel: funnel,
                                          actions: [{ 'type' => 'move_to_stage',
                                                      'params' => { 'stage_id' => 0 } }])
        described_class.call(rule: rule, task: task)
        expect(rule.reload.last_error_message).to include('not in funnel')
      end
    end

    context 'when a non-critical action fails' do
      it 'continues with the remaining actions' do
        rule = create(:kanban_automation, account: account, funnel: funnel,
                                          actions: [
                                            { 'type' => 'assign_user', 'params' => { 'user_ids' => [-1] } },
                                            { 'type' => 'set_priority', 'params' => { 'priority' => 'urgent' } }
                                          ])
        described_class.call(rule: rule, task: task)
        expect(task.reload.priority).to eq('urgent')
      end
    end
  end
end
