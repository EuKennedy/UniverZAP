class Ai::Invocation < ApplicationRecord
  self.table_name = 'ai_invocations'

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account

  PHASES = %w[main classifier router summary summarize suggest autopilot rewrite chat copilot_chat].freeze
  STATUSES = %w[success error].freeze

  validates :phase, inclusion: { in: PHASES }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
end
