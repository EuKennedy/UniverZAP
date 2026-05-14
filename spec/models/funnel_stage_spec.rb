# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FunnelStage do
  describe 'associations' do
    it { is_expected.to belong_to(:funnel) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(120) }
  end

  describe 'color format' do
    it 'accepts hex colors' do
      stage = build(:funnel_stage, color: '#FF00AA')
      expect(stage).to be_valid
    end

    it 'rejects invalid colors' do
      stage = build(:funnel_stage, color: 'red')
      expect(stage).not_to be_valid
    end
  end

  describe 'status_type enum' do
    it 'defaults to active' do
      expect(create(:funnel_stage)).to be_active
    end
  end
end
