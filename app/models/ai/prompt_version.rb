# A snapshot of the instructions a human wrote for the agent, plus the examples
# it should imitate.
#
# The agent keeps working exactly as before when no version exists: the prompt
# assembly falls back to `ai_assistants.system_prompt`. A version only takes
# over once someone promotes it, and promotion is gated on evidence
# (Ai::PromotionPolicy), never on someone feeling good about the wording.
class Ai::PromptVersion < ApplicationRecord
  self.table_name = 'ai_prompt_versions'

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :ab_comparisons, class_name: 'Ai::AbComparison', foreign_key: :ai_prompt_version_id,
                            inverse_of: :ai_prompt_version, dependent: :destroy

  STATUSES = %w[draft testing live archived].freeze
  MAX_FEW_SHOTS = 8

  validates :version, presence: true, length: { maximum: 20 }
  validates :status, inclusion: { in: STATUSES }
  validates :system_prompt, length: { maximum: 60_000 }

  scope :live, -> { where(status: 'live') }
  scope :candidates, -> { where(status: %w[draft testing]) }
  scope :newest_first, -> { order(created_at: :desc) }

  # Few-shot examples are capped and rotated: past a handful they stop teaching
  # a pattern and start dominating the prompt, and the model begins reciting the
  # examples instead of answering the customer.
  def few_shot_pairs
    Array(few_shots).first(MAX_FEW_SHOTS).filter_map do |pair|
      next if pair['question'].blank? || pair['answer'].blank?

      { 'question' => pair['question'].to_s, 'answer' => pair['answer'].to_s }
    end
  end

  def push_event_data
    {
      id: id, version: version, status: status, win_rate: win_rate,
      few_shots: few_shot_pairs, learnings: Array(learnings).length,
      promoted_at: promoted_at&.to_i, created_at: created_at.to_i
    }
  end
end
