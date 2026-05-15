# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Funnel do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:funnel_stages).dependent(:destroy) }
    it { is_expected.to have_many(:inboxes).through(:funnel_inboxes) }
    it { is_expected.to have_many(:agents).through(:funnel_agents) }
    it { is_expected.to have_many(:kanban_tasks).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(120) }
  end

  describe 'position assignment' do
    let(:account) { create(:account) }

    it 'auto-increments position per account' do
      first = create(:funnel, account: account)
      second = create(:funnel, account: account)
      expect(second.position).to eq(first.position + 1)
    end
  end

  describe 'automation_settings validation' do
    let(:funnel) { build(:funnel) }

    it 'accepts known keys' do
      funnel.automation_settings = { 'auto_create_task_for_new_conversation' => true }
      expect(funnel).to be_valid
    end

    it 'rejects unknown keys' do
      funnel.automation_settings = { 'unknown_flag' => true }
      expect(funnel).not_to be_valid
    end
  end
end
