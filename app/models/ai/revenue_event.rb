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

  # The rows Ai::Belezaki::BookingRecorder wrote, and only those.
  #
  # The salon holds the book, so a belezaki appointment leaves no row in
  # ai_calendar_appointments at all: this ledger is where it lands, keyed by the
  # salon's own appointment id. Matching on that prefix is exact, so the day
  # something else starts posting bookings here this cannot reach its rows.
  #
  # It lives on the model rather than inside a reader because TWO different
  # readers need it now — the commercial panel counts these bookings and the
  # manager's time check compares their hour against what the agent said — and
  # two hand-written copies of the same criterion is how one of them silently
  # stops matching the day the prefix changes.
  scope :belezaki_bookings, lambda {
    where(recorded_by: Ai::Belezaki::BookingRecorder::RECORDER)
      .where('external_ref LIKE ?', "#{Ai::Belezaki::BookingRecorder::REF_PREFIX}%")
  }

  # Bookings the agent made outside business hours are the single strongest
  # argument for the module: they would not exist, because nobody was there.
  AFTER_HOURS = ((19..23).to_a + (0..8).to_a).freeze

  # Evaluated in Ruby, in the BUSINESS's timezone, NOT in SQL. `EXTRACT(HOUR
  # FROM occurred_at)` reads the stored UTC value, so a sale at 21h in São Paulo
  # is midnight to Postgres and 8h is 5h: the whole point of the number is the
  # local clock of the business, and getting it wrong shifts every row by three
  # hours in the one metric the operator quotes to justify the module.
  #
  # The zone has to be passed in, and this used to read `Time.zone` instead.
  # `Time.zone` is UTC on this installation — nothing sets config.time_zone — so
  # the reading was doing precisely what the paragraph above forbids: a booking
  # taken at 21h in São Paulo counted as midnight, and one at 6h counted as 3h.
  # Ai::Reports::AccountClock works out what local means for an account, from
  # what the operator already told us. The default is kept so a caller with no
  # account in hand still gets an answer rather than an exception.
  def after_hours?(zone = Time.zone)
    local = occurred_at.in_time_zone(zone)
    local.sunday? || AFTER_HOURS.include?(local.hour)
  end

  def push_event_data
    {
      id: id, source: source, amount_brl: amount_brl.to_f, occurred_at: occurred_at.to_i,
      conversation_id: conversation_id, contact_id: contact_id,
      recorded_by: recorded_by, external_ref: external_ref
    }
  end
end
