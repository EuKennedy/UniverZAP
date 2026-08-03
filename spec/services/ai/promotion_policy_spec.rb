# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::PromotionPolicy do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:version) { create(:ai_prompt_version, ai_assistant: assistant, account: account) }

  def duel(winner: 'b', cost_a: 0.01, cost_b: 0.01, latency_b: 1000, critical: false)
    invocation = create(:ai_invocation, account: account, ai_assistant: assistant,
                                        ai_response: 'a', cost_brl: cost_a, duration_ms: 1000)
    create(:ai_ab_comparison, account: account, ai_assistant: assistant,
                              ai_invocation: invocation, ai_prompt_version: version,
                              winner: winner, critical_loss: critical,
                              telemetry_b: { 'cost_brl' => cost_b, 'latency_ms' => latency_b })
  end

  def passing_batch(count: 20, **overrides)
    count.times { duel(**overrides) }
  end

  describe 'the sample gate' do
    # A percentage over three duels is noise wearing a number.
    it 'blocks below the minimum number of judged comparisons' do
      passing_batch(count: described_class::MIN_COMPARISONS - 1)

      report = described_class.new(version: version).report
      expect(report[:promotable]).to be(false)
      expect(report[:checks][:sample][:pass]).to be(false)
    end

    it 'ignores unjudged duels when counting the sample' do
      passing_batch
      5.times { duel(winner: nil) }

      expect(described_class.new(version: version).report[:total]).to eq(20)
    end
  end

  describe 'the win rate gate' do
    it 'blocks a statistical tie' do
      10.times { duel(winner: 'b') }
      10.times { duel(winner: 'a') }

      expect(described_class.new(version: version).report[:checks][:win_rate][:pass]).to be(false)
    end

    it 'passes a clear improvement' do
      passing_batch

      expect(described_class.new(version: version)).to be_promotable
    end
  end

  describe 'the critical loss gate' do
    # One fabricated price is disqualifying no matter how good the average is.
    it 'blocks on a single unsourced value, even with a perfect win rate' do
      passing_batch
      duel(winner: 'b', critical: true)

      expect(described_class.new(version: version)).not_to be_promotable
    end

    # A fabricated price is a fact about the candidate, not an opinion someone
    # still has to vote on.
    it 'counts a critical loss that nobody has judged yet' do
      passing_batch
      duel(winner: nil, critical: true)

      expect(described_class.new(version: version).report[:checks][:critical_losses][:value]).to eq(1)
    end
  end

  describe 'the cost gate' do
    it 'blocks a candidate that triples the credit burn' do
      passing_batch(cost_a: 0.01, cost_b: 0.03)

      expect(described_class.new(version: version).report[:checks][:cost][:pass]).to be(false)
    end

    it 'allows a modest increase' do
      passing_batch(cost_a: 0.01, cost_b: 0.012)

      expect(described_class.new(version: version).report[:checks][:cost][:pass]).to be(true)
    end
  end

  describe 'the latency gate' do
    # An agent that is fast on average and occasionally takes twelve seconds
    # still loses the customer who waited twelve seconds.
    it 'blocks when the slow tail is real' do
      17.times { duel(latency_b: 500) }
      3.times { duel(latency_b: 12_000) }

      expect(described_class.new(version: version).report[:checks][:latency][:pass]).to be(false)
    end

    # Nearest-rank, not "the maximum": a single outlier in twenty is noise, and
    # blocking a promotion on it while calling the number a percentile would be
    # a gate that lies about what it measured.
    it 'tolerates a single outlier in twenty' do
      19.times { duel(latency_b: 500) }
      duel(latency_b: 12_000)

      expect(described_class.new(version: version).report[:checks][:latency][:pass]).to be(true)
    end
  end

  describe 'an untested version' do
    it 'is never promotable and reports no win rate instead of zero' do
      report = described_class.new(version: version).report

      expect(report[:promotable]).to be(false)
      expect(report[:win_rate]).to be_nil
    end
  end
end
