# The human verdict on what the agent said.
#
# The guardrail flags in Ai::Reports::InvocationMetrics are the machine's
# opinion, and a machine that grades itself is not a quality signal. These rows
# are somebody on the team having read the reply and said so, which is the only
# number here that can contradict the agent.
#
# `pending` matters as much as the ratings: a correction nobody applied is work
# already done that the agent has not learned from yet, and it silently decays
# into a screen full of the same complaint.
class Ai::Reports::QualityMetrics
  def initialize(account:, period:)
    @account = account
    @period = period
  end

  def totals
    @totals ||= build_totals
  end

  # Memoized, like every public reader here: the orchestrator asks by_agent once
  # per row of the comparison table, and an unmemoized reader turns a fixed
  # number of queries into one per agent.
  def by_agent
    @by_agent ||= build_by_agent
  end

  private

  def build_totals
    counts = scope.group(:rating).count
    reviewed = counts.values.sum
    {
      reviewed: reviewed,
      up: counts['up'].to_i, down: counts['down'].to_i, ideal: counts['ideal'].to_i,
      approval_rate: approval_rate(counts, reviewed),
      pending_application: scope.pending_application.count,
      by_reason: scope.where.not(reason: nil).group(:reason).count
    }
  end

  def build_by_agent
    grouped = scope.group(:ai_assistant_id, :rating).count
    grouped.each_with_object({}) do |((assistant_id, rating), count), out|
      row = (out[assistant_id] ||= { 'up' => 0, 'down' => 0, 'ideal' => 0 })
      row[rating] = count
    end
  end

  def scope
    @scope ||= Ai::ResponseFeedback.where(account_id: @account.id, created_at: @period.range)
  end

  # NULL rather than 100% when nobody reviewed anything. A fresh account showing
  # a perfect score is the panel inventing praise nobody gave.
  def approval_rate(counts, reviewed)
    return nil if reviewed.zero?

    ((counts['up'].to_i + counts['ideal'].to_i).to_f / reviewed * 100).round(1)
  end
end
