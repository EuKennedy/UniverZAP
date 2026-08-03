# One person's verdict on one agent reply.
#
# The automatic guardrails can only say "this looks risky". This is the only
# place in the module where someone who knows the business says what the answer
# should have been, and it is what the agent learns from.
class Ai::ResponseFeedback < ApplicationRecord
  self.table_name = 'ai_response_feedbacks'

  belongs_to :ai_invocation, class_name: 'Ai::Invocation'
  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account
  belongs_to :reviewer, class_name: 'User'
  belongs_to :ai_training, class_name: 'Ai::Training', optional: true
  belongs_to :ai_intent, class_name: 'Ai::Intent', optional: true

  RATINGS = %w[up down ideal].freeze
  REASONS = %w[info_incorreta preco_inventado tom_inadequado deveria_transbordar nao_entendeu].freeze

  # Facts (price, hours, policy) must correct the very NEXT customer, so these
  # are applied the moment they are saved. Tone is deliberately absent: style
  # changes how the agent behaves everywhere, so it only goes live through a
  # prompt version that was A/B tested first.
  IMMEDIATE_REASONS = %w[info_incorreta preco_inventado deveria_transbordar nao_entendeu].freeze

  CORRECTION_MAX_CHARS = 20_000

  validates :rating, inclusion: { in: RATINGS }
  validates :reason, inclusion: { in: REASONS }, allow_nil: true
  # A thumbs-down with no reason is a shrug: it cannot be routed anywhere and it
  # teaches the agent nothing.
  validates :reason, presence: true, if: -> { rating == 'down' }
  validates :corrected_text, length: { maximum: CORRECTION_MAX_CHARS }

  scope :approvals, -> { where(rating: %w[up ideal]) }
  scope :corrections, -> { where(rating: 'down') }
  scope :exemplars, -> { where(rating: 'ideal') }
  scope :pending_application, -> { corrections.where(applied_at: nil) }

  def immediate?
    rating == 'down' && IMMEDIATE_REASONS.include?(reason) && corrected_text.present?
  end

  def applied?
    applied_at.present?
  end

  def push_event_data
    {
      id: id, rating: rating, reason: reason, corrected_text: corrected_text,
      applied_at: applied_at&.to_i, ai_training_id: ai_training_id, ai_intent_id: ai_intent_id,
      reviewer_id: reviewer_id, created_at: created_at.to_i
    }
  end
end
