# The five conditions a candidate version must meet before it can answer real
# customers. Nothing goes live on a hunch.
#
# Each threshold buys something specific:
#   sample     — a percentage over three duels is noise wearing a number.
#   win rate   — 70% is a clear improvement, not a statistical tie.
#   critical   — one fabricated price is disqualifying no matter the average.
#   cost       — quality must not quietly triple the operator's credit burn.
#   latency    — past four seconds a WhatsApp customer stops waiting.
class Ai::PromotionPolicy
  MIN_COMPARISONS = 20
  MIN_WIN_RATE = 0.70
  MAX_COST_RATIO = 1.4
  MAX_P95_LATENCY_MS = 4000

  def initialize(version:)
    @version = version
    @judged = version.ab_comparisons.judged
  end

  # Every check, with the measured value next to it, so the UI can explain why
  # the button is disabled instead of just disabling it.
  def report
    {
      promotable: checks.values.all? { |check| check[:pass] },
      checks: checks,
      total: @judged.count,
      win_rate: win_rate
    }
  end

  def promotable?
    report[:promotable]
  end

  private

  def checks
    @checks ||= {
      sample: check(@judged.count >= MIN_COMPARISONS, @judged.count, MIN_COMPARISONS),
      win_rate: check(win_rate.to_f >= MIN_WIN_RATE, win_rate, MIN_WIN_RATE),
      critical_losses: check(critical_losses.zero?, critical_losses, 0),
      cost: check(cost_ratio.nil? || cost_ratio <= MAX_COST_RATIO, cost_ratio, MAX_COST_RATIO),
      latency: check(p95_latency_b <= MAX_P95_LATENCY_MS, p95_latency_b, MAX_P95_LATENCY_MS)
    }
  end

  def check(pass, value, limit)
    { pass: pass, value: value, limit: limit }
  end

  def win_rate
    total = @judged.count
    return nil if total.zero?

    (@judged.won_by_b.count.to_f / total).round(3)
  end

  # Counted over EVERY comparison, judged or not. A fabricated price is a fact
  # about the candidate, not an opinion someone still has to vote on.
  def critical_losses
    @critical_losses ||= @version.ab_comparisons.critical_losses.count
  end

  def cost_ratio
    a = average(:a, 'cost_brl')
    b = average(:b, 'cost_brl')
    return nil if a.nil? || a.zero? || b.nil?

    (b / a).round(3)
  end

  # p95 rather than the mean: an agent that is fast on average and occasionally
  # takes twelve seconds still loses the customer who waited twelve seconds.
  #
  # Nearest-rank, the textbook definition. The obvious shortcut
  # (`values[(n - 1) * 0.95]` rounded up) returns the MAXIMUM for any sample
  # under about forty, which would have called a single slow outlier "the p95"
  # and blocked promotions on noise while claiming to measure a percentile.
  def p95_latency_b
    values = telemetry_values(:b, 'latency_ms').sort
    return 0 if values.empty?

    values[[(values.length * 0.95).ceil - 1, 0].max].to_i
  end

  def average(side, key)
    values = telemetry_values(side, key)
    return nil if values.empty?

    values.sum / values.length
  end

  def telemetry_values(side, key)
    @judged.includes(:ai_invocation).filter_map do |comparison|
      source = side == :a ? comparison.telemetry_a : comparison.telemetry_b
      value = source[key]
      value&.to_f
    end
  end
end
