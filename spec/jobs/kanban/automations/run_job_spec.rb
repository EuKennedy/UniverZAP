require 'rails_helper'

RSpec.describe Kanban::Automations::RunJob, type: :job do
  let(:account)    { create(:account) }
  let(:funnel)     { create(:funnel, account: account) }
  let(:stage)      { create(:funnel_stage, funnel: funnel) }
  let(:task)       { create(:kanban_task, account: account, funnel: funnel, funnel_stage: stage) }
  let(:rule) do
    create(:kanban_automation, account: account, funnel: funnel,
                               actions: [{ type: 'set_priority', params: { priority: 'urgent' } }])
  end

  it 'runs the executor for matching rule + task' do
    described_class.perform_now(rule.id, task.id, {})
    expect(task.reload.priority).to eq('urgent')
  end

  it 'no-ops when rule or task is missing' do
    expect { described_class.perform_now(0, 0, {}) }.not_to raise_error
  end

  it 'refuses to run when tenant ids mismatch (defense-in-depth)' do
    foreign_task = create(:kanban_task)
    expect(Kanban::Automations::Executor).not_to receive(:call)
    expect(Rails.logger).to receive(:error).with(/TENANT MISMATCH/)
    described_class.perform_now(rule.id, foreign_task.id, {})
  end
end
