# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::PricingCalculator do
  describe '.cost_cents_brl' do
    it 'computes the BRL-cents cost for a Sonnet call with the default 2x markup' do
      # 1000 input + 500 output Sonnet tokens => (1000 * 3 + 500 * 15) / 1e6 = $0.0105
      # × 5 BRL/USD × 2 markup × 100 cents = ~10.5 cents → rounded to 11
      cost = described_class.cost_cents_brl(model: 'claude-sonnet-4-5', input_tokens: 1_000, output_tokens: 500)
      expect(cost).to eq(11)
    end

    it 'is materially cheaper for Haiku than Sonnet' do
      sonnet = described_class.cost_cents_brl(model: 'claude-sonnet-4-5', input_tokens: 10_000, output_tokens: 5_000)
      haiku  = described_class.cost_cents_brl(model: 'claude-haiku-4-5',  input_tokens: 10_000, output_tokens: 5_000)
      expect(haiku).to be < sonnet
    end

    it 'falls back to Sonnet pricing when the model is unknown' do
      unknown = described_class.cost_cents_brl(model: 'claude-fake-1', input_tokens: 1_000, output_tokens: 500)
      sonnet  = described_class.cost_cents_brl(model: 'claude-sonnet-4-5', input_tokens: 1_000, output_tokens: 500)
      expect(unknown).to eq(sonnet)
    end
  end

  describe '.estimated_cost_cents_brl' do
    it 'caps the pre-call estimate at the configured max_output_tokens' do
      # Pre-call quota check should always be >= the post-call debit
      pre  = described_class.estimated_cost_cents_brl(model: 'claude-sonnet-4-5', max_output_tokens: 1_024)
      post = described_class.cost_cents_brl(model: 'claude-sonnet-4-5', input_tokens: 2_000, output_tokens: 512)
      expect(pre).to be >= post
    end
  end

  describe '.estimated_conversations' do
    it 'returns a non-negative count for any positive balance' do
      expect(described_class.estimated_conversations(5_000)).to be >= 1
    end

    it 'returns zero when the per-turn cost cannot be computed' do
      expect(described_class.estimated_conversations(0)).to eq(0)
    end
  end
end
