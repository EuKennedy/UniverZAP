class Ai::Invocation < ApplicationRecord
  self.table_name = 'ai_invocations'

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account
  has_many :response_feedbacks, class_name: 'Ai::ResponseFeedback', foreign_key: :ai_invocation_id,
                                inverse_of: :ai_invocation, dependent: :destroy
  # NULLIFY, never destroy. Deleting an agent cascades to its invocations, and
  # each one may have charged the account — the ledger entry is the record of
  # that charge. Losing it would rewrite the account's spend history because
  # somebody tidied up an agent, so the entry stays and simply forgets which
  # call produced it. Without this the whole delete failed on a foreign key and
  # the operator got an Internal Server Error with no way to remove the agent.
  has_many :credit_ledger_entries, class_name: 'Ai::CreditLedgerEntry', foreign_key: :ai_invocation_id,
                                   inverse_of: :ai_invocation, dependent: :nullify

  # `replay` is the A/B lab. It is billed like any other call, but it is an
  # experiment, not customer service, so the ROI panel excludes it: counting it
  # as the cost of serving customers would make a well-tested agent look
  # expensive precisely because it was well tested.
  # `transcription` is a voice note turned into text before the agent can read
  # it. It is billed per minute of audio rather than per token, which is why it
  # carries no token counts.
  PHASES = %w[
    main classifier router summary summarize suggest autopilot rewrite chat copilot_chat replay transcription
  ].freeze
  STATUSES = %w[success error].freeze
  # Delivery of the customer-facing reply this call produced. NULL on calls that
  # never had a delivery of their own (tool-loop iterations, summaries).
  DELIVERY_STATUSES = %w[pending sent failed].freeze

  # Automatic review flags. Ordered by severity: the supervision queue shows the
  # first one that applies, because a reply that invented a price needs a human
  # before one that merely sounded unsure.
  AUTO_FLAGS = %w[
    preco_inventado
    horario_divergente
    cliente_insatisfeito
    promessa_solta
    sem_fonte
    baixa_confianca
  ].freeze

  # An explicit validator here disables the generic 20k text cap in
  # ApplicationRecord. Without it a system prompt carrying a large catalogue
  # would fail validation, and because invocation logging is rescued, the reply
  # would go out with no log at all: exactly the audit hole this table exists to
  # close.
  SNAPSHOT_MAX_CHARS = 80_000

  validates :phase, inclusion: { in: PHASES }
  validates :status, inclusion: { in: STATUSES }
  validates :delivery_status, inclusion: { in: DELIVERY_STATUSES }, allow_nil: true
  validates :auto_flag, inclusion: { in: AUTO_FLAGS }, allow_nil: true
  validates :system_prompt, :user_message, :ai_response,
            length: { maximum: SNAPSHOT_MAX_CHARS }, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }
  # Calls that produced a message the customer actually received.
  scope :replies, -> { where.not(message_id: nil) }
  scope :flagged, -> { where.not(auto_flag: nil) }
  scope :awaiting_delivery, -> { where(delivery_status: 'pending') }
  # Real customers only. Playground turns are billed, so they belong in cost
  # reports, but reviewing an answer given to a fake customer is busywork.
  scope :live, -> { where(sandbox: false) }

  # Severity order, so a call that tripped several guardrails surfaces under the
  # one a human should look at first.
  def self.primary_flag(flags)
    AUTO_FLAGS.find { |flag| flags.include?(flag) }
  end
end
