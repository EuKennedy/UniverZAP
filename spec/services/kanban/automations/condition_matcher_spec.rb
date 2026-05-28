require 'rails_helper'

RSpec.describe Kanban::Automations::ConditionMatcher do
  let(:account) { create(:account) }
  let(:funnel)  { create(:funnel, account: account) }
  let(:stage)   { create(:funnel_stage, funnel: funnel) }
  let(:task)    { create(:kanban_task, account: account, funnel: funnel, funnel_stage: stage, priority: 'high') }

  describe '.matches?' do
    it 'matches an empty conditions hash' do
      rule = build(:kanban_automation, conditions: {})
      expect(described_class.matches?(rule: rule, task: task)).to be true
    end

    it 'matches priority_in' do
      rule = build(:kanban_automation, conditions: { 'priority_in' => %w[high urgent] })
      expect(described_class.matches?(rule: rule, task: task)).to be true
    end

    it 'does not match when priority_in excludes the task priority' do
      rule = build(:kanban_automation, conditions: { 'priority_in' => %w[low medium] })
      expect(described_class.matches?(rule: rule, task: task)).to be false
    end

    it 'matches stage_id_in' do
      rule = build(:kanban_automation, conditions: { 'stage_id_in' => [stage.id] })
      expect(described_class.matches?(rule: rule, task: task)).to be true
    end

    it 'matches event-scoped from_stage_id_in via payload' do
      rule = build(:kanban_automation, conditions: { 'from_stage_id_in' => [99] })
      expect(described_class.matches?(rule: rule, task: task, event_payload: { from_stage_id: 99 })).to be true
    end

    it 'fails closed on unknown condition keys' do
      rule = build(:kanban_automation, conditions: { 'unknown_key' => 'whatever' })
      expect(described_class.matches?(rule: rule, task: task)).to be false
    end

    it 'requires every condition to match (AND semantics)' do
      rule = build(:kanban_automation, conditions: {
                     'priority_in' => ['high'],
                     'stage_id_in' => [stage.id + 999]
                   })
      expect(described_class.matches?(rule: rule, task: task)).to be false
    end

    it 'matches has_assignee=false when task has no assignees' do
      rule = build(:kanban_automation, conditions: { 'has_assignee' => false })
      expect(described_class.matches?(rule: rule, task: task)).to be true
    end

    it 'matches due_in_hours_lte when task has near due_date' do
      task.update!(due_date: 2.hours.from_now)
      rule = build(:kanban_automation, conditions: { 'due_in_hours_lte' => 24 })
      expect(described_class.matches?(rule: rule, task: task)).to be true
    end
  end
end
