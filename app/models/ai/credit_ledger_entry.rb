class Ai::CreditLedgerEntry < ApplicationRecord
  self.table_name = 'ai_credit_ledger_entries'

  KINDS = %w[grant purchase grace consumption refund adjustment].freeze

  belongs_to :account
  belongs_to :ai_invocation, class_name: 'Ai::Invocation', optional: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :amount_cents_brl, presence: true

  scope :credits,       -> { where('amount_cents_brl > 0') }
  scope :debits,        -> { where('amount_cents_brl < 0') }
  scope :consumptions,  -> { where(kind: 'consumption') }
  scope :purchases,     -> { where(kind: 'purchase') }
  scope :within,        ->(range) { where(created_at: range) }
  scope :recent,        -> { order(created_at: :desc) }
end
