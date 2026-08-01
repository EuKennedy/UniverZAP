require 'rails_helper'

RSpec.describe Redis::SlidingWindowRateLimiter do
  let(:key) { 'test_sliding_window::42' }
  let(:limiter) { described_class.new(key, limit: 3, window: 60) }

  after { Redis::Alfred.delete(key) }

  describe '#exceeded?' do
    it 'is false while the number of hits stays below the limit' do
      2.times { limiter.record! }

      expect(limiter.exceeded?).to be(false)
    end

    it 'is true once the limit is reached' do
      3.times { limiter.record! }

      expect(limiter.exceeded?).to be(true)
    end
  end

  describe '#count' do
    it 'counts each recorded hit' do
      expect { limiter.record! }.to change(limiter, :count).from(0).to(1)
    end

    it 'prunes hits that fell out of the window' do
      stale_score = Time.now.to_f - 61 # window is 60s, so this is expired
      Redis::Alfred.zadd(key, stale_score, "stale:#{stale_score}")
      limiter.record!

      expect(limiter.count).to eq(1)
    end
  end
end
