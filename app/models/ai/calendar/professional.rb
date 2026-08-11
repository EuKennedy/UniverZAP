# A person with an agenda — in practice, one Google calendar.
#
# The MVP creates exactly one of these on connect and never shows the word to
# the operator: the screen says "agenda do salão". It exists from day one so
# that growing to three chairs is an INSERT rather than a migration, and so that
# "tem horário às 15h?" always has a defined answer — it means "with whom".
class Ai::Calendar::Professional < ApplicationRecord
  self.table_name = 'ai_calendar_professionals'

  belongs_to :connection, class_name: 'Ai::Calendar::Connection',
                          foreign_key: :ai_calendar_connection_id, inverse_of: :professionals
  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account

  has_many :hours, class_name: 'Ai::Calendar::Hour',
                   foreign_key: :ai_calendar_professional_id, dependent: :destroy, inverse_of: :professional
  has_many :service_professionals, class_name: 'Ai::Calendar::ServiceProfessional',
                                   foreign_key: :ai_calendar_professional_id, dependent: :destroy, inverse_of: :professional
  # `:destroy`, not `:restrict`: deleting an agent already blew up on a foreign
  # key twice in this codebase, and a scheduling table must not be the third.
  # The events themselves stay in Google — removing an agent is not a reason to
  # wipe somebody's calendar.
  has_many :appointments, class_name: 'Ai::Calendar::Appointment',
                          foreign_key: :ai_calendar_professional_id, dependent: :destroy, inverse_of: :professional

  validates :name, presence: true
  validates :calendar_id, presence: true, uniqueness: { scope: :ai_calendar_connection_id }
  validates :timezone, presence: true

  scope :active, -> { where(active: true) }

  # Everything this person can perform: the services the whole business offers,
  # plus the ones assigned specifically to them.
  def services
    Ai::Calendar::Service.active.where(ai_assistant_id: ai_assistant_id)
                         .where(global: true)
                         .or(Ai::Calendar::Service.active.where(id: service_professionals.select(:ai_calendar_service_id)))
  end

  # The week as the operator filled it in: ranges per weekday, so a lunch break
  # is two rows rather than a gap nobody modelled.
  def hours_by_weekday
    hours.order(:weekday, :starts_at).group_by(&:weekday)
  end

  def push_event_data
    {
      id: id, name: name, calendar_id: calendar_id, timezone: timezone, active: active,
      hours: hours.order(:weekday, :starts_at).map(&:push_event_data)
    }
  end
end
