# One sale credited to the agent.
class Ai::RevenueEvent < ApplicationRecord
  self.table_name = 'ai_revenue_events'

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true
  belongs_to :ai_lead_opportunity, class_name: 'Ai::LeadOpportunity', optional: true

  SOURCES = %w[agendamento assinatura pedido recuperado].freeze
  RECORDERS = %w[operator integration agent].freeze

  # How long after a conversation a sale can still plausibly be credited to it.
  # Straight from the spec, and deliberately different per source: a booking is
  # immediate, a subscription takes a week of thinking.
  ATTRIBUTION_WINDOW = {
    'agendamento' => 0.days,
    'pedido' => 72.hours,
    'assinatura' => 7.days,
    'recuperado' => 15.days
  }.freeze

  validates :source, inclusion: { in: SOURCES }
  validates :recorded_by, inclusion: { in: RECORDERS }
  validates :amount_brl, numericality: { greater_than_or_equal_to: 0 }

  scope :in_period, ->(days) { where(occurred_at: days.days.ago..) }

  # Bookings the agent made outside business hours are the single strongest
  # argument for the module: they would not exist, because nobody was there.
  AFTER_HOURS = (19..23).to_a + (0..8).to_a

  scope :after_hours, lambda {
    where("EXTRACT(HOUR FROM occurred_at) = ANY (ARRAY[#{AFTER_HOURS.join(',')}]) " \
          'OR EXTRACT(DOW FROM occurred_at) = 0')
  }

  def push_event_data
    {
      id: id, source: source, amount_brl: amount_brl.to_f, occurred_at: occurred_at.to_i,
      conversation_id: conversation_id, contact_id: contact_id,
      recorded_by: recorded_by, external_ref: external_ref
    }
  end
end
