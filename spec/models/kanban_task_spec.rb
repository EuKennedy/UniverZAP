# frozen_string_literal: true

require 'rails_helper'

RSpec.describe KanbanTask do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:funnel) }
    it { is_expected.to belong_to(:funnel_stage) }
    it { is_expected.to have_many(:assignees).through(:kanban_task_assignees) }
    it { is_expected.to have_many(:task_labels).through(:kanban_task_labels) }
    it { is_expected.to have_many(:conversations).through(:kanban_task_conversations) }
    it { is_expected.to have_many(:contacts).through(:kanban_task_contacts) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_most(255) }
  end

  describe 'display_id assignment' do
    let(:account) { create(:account) }
    let(:funnel) { create(:funnel, account: account) }
    let!(:stage) { create(:funnel_stage, funnel: funnel) }

    it 'auto-increments display_id per account' do
      first = create(:kanban_task, account: account, funnel: funnel, funnel_stage: stage)
      second = create(:kanban_task, account: account, funnel: funnel, funnel_stage: stage)
      expect(second.display_id).to eq(first.display_id + 1)
    end
  end

  describe 'cross-account guard' do
    it 'rejects funnel_stage from a different funnel' do
      account = create(:account)
      funnel_a = create(:funnel, account: account)
      funnel_b = create(:funnel, account: account)
      stage_b = create(:funnel_stage, funnel: funnel_b)
      task = build(:kanban_task, account: account, funnel: funnel_a, funnel_stage: stage_b)
      expect(task).not_to be_valid
    end
  end
end
