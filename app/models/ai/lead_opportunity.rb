# A conversation that ended without a sale, with a score for how worth chasing
# it is.
class Ai::LeadOpportunity < ApplicationRecord
  self.table_name = 'ai_lead_opportunities'

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account
  belongs_to :contact
  belongs_to :conversation, optional: true

  STATUSES = %w[open followed won lost].freeze
  BLOCK_REASONS = %w[pediu_preco sem_vaga comparando checkout_abandonado sem_resposta outro].freeze

  # Bands, and what each one earns. A hot lead that waits a day is a cold lead.
  HOT_FLOOR = 80
  WARM_FLOOR = 50

  validates :status, inclusion: { in: STATUSES }
  validates :temperature, numericality: { in: 0..100 }
  validates :block_reason, inclusion: { in: BLOCK_REASONS }, allow_nil: true

  scope :open_leads, -> { where(status: 'open') }
  scope :hot, -> { where(temperature: HOT_FLOOR..) }
  scope :warm, -> { where(temperature: WARM_FLOOR...HOT_FLOOR) }
  scope :cold, -> { where(temperature: ...WARM_FLOOR) }
  scope :hottest_first, -> { order(temperature: :desc, last_seen_at: :desc) }

  def band
    return 'hot' if temperature >= HOT_FLOOR
    return 'warm' if temperature >= WARM_FLOOR

    'cold'
  end

  def push_event_data
    {
      id: id, contact_id: contact_id, contact_name: contact&.name,
      conversation_id: conversation_id, interest: interest,
      potential_brl: potential_brl.to_f, temperature: temperature, band: band,
      block_reason: block_reason, suggested_action: suggested_action,
      status: status, won_brl: won_brl&.to_f,
      last_seen_at: last_seen_at.to_i, followed_up_at: followed_up_at&.to_i,
      signals: signals
    }
  end
end
