# Our index of what WE booked. Deliberately not a mirror of the calendar:
# Google stays the single source of truth for availability, because the owner
# books from their phone without passing through us and any copy would be born
# wrong.
#
# This exists to answer the one question Google cannot: which event belongs to
# this customer. That is what rescheduling and cancelling need, and it is also
# the boundary that keeps the agent off appointments it did not create — the
# dentist, the lunch, anything the owner put there by hand stays untouchable
# while still counting as occupied time.
class Ai::Calendar::Appointment < ApplicationRecord
  self.table_name = 'ai_calendar_appointments'

  STATUSES = %w[booked cancelled].freeze

  belongs_to :professional, class_name: 'Ai::Calendar::Professional',
                            foreign_key: :ai_calendar_professional_id, inverse_of: :appointments
  belongs_to :service, class_name: 'Ai::Calendar::Service', foreign_key: :ai_calendar_service_id, optional: true
  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account
  belongs_to :contact
  belongs_to :conversation, optional: true

  validates :google_event_id, presence: true, uniqueness: true
  validates :starts_at, :ends_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :booked, -> { where(status: 'booked') }
  scope :upcoming, -> { where(starts_at: Time.current..) }

  # Everything the agent is allowed to touch for this customer, and nothing
  # else. Scoped by contact AND by assistant, so one workspace's agent can never
  # reach another's appointment even if an id were crossed.
  def self.reachable_by(assistant, contact)
    booked.upcoming.where(ai_assistant_id: assistant.id, contact_id: contact.id).order(:starts_at)
  end

  # Too close to the appointment for the agent to act on its own. The operator
  # sets the window; past it the agent explains rather than moves things.
  def within_cancellation_window?(hours)
    starts_at <= hours.to_i.hours.from_now
  end
end
