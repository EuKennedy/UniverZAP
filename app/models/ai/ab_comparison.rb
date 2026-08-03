# One duel: the reply a customer really received, next to what a candidate
# version would have said to the same question.
#
# Column A is never regenerated. It comes from the log, because the point of the
# comparison is to judge a candidate against reality, not against a fresh roll
# of the same dice.
class Ai::AbComparison < ApplicationRecord
  self.table_name = 'ai_ab_comparisons'

  belongs_to :ai_invocation, class_name: 'Ai::Invocation'
  belongs_to :ai_prompt_version, class_name: 'Ai::PromptVersion'
  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account
  belongs_to :reviewer, class_name: 'User', optional: true

  WINNERS = %w[a b tie].freeze

  validates :winner, inclusion: { in: WINNERS }, allow_nil: true
  validates :response_b, length: { maximum: 60_000 }

  scope :judged, -> { where.not(winner: nil) }
  scope :won_by_b, -> { where(winner: 'b') }
  scope :critical_losses, -> { where(critical_loss: true) }

  def push_event_data
    {
      id: id, winner: winner, critical_loss: critical_loss,
      response_a: ai_invocation.ai_response.to_s, response_b: response_b.to_s,
      user_message: ai_invocation.user_message.to_s,
      telemetry_a: telemetry_a, telemetry_b: telemetry_b,
      created_at: created_at.to_i
    }
  end

  # Read from the log, so the cost of the answer the customer got is a fact,
  # not an estimate.
  def telemetry_a
    {
      'cost_brl' => ai_invocation.cost_brl.to_f,
      'latency_ms' => ai_invocation.duration_ms,
      'confidence' => ai_invocation.confidence,
      'chunks' => Array(ai_invocation.chunks_used).length
    }
  end
end
