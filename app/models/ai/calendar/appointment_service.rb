# Which services an appointment covers. "Progressiva + corte" is one block on
# the agenda with the durations summed, so an appointment points at several.
class Ai::Calendar::AppointmentService < ApplicationRecord
  self.table_name = 'ai_calendar_appointment_services'

  belongs_to :appointment, class_name: 'Ai::Calendar::Appointment',
                           foreign_key: :ai_calendar_appointment_id, inverse_of: :appointment_services
  belongs_to :service, class_name: 'Ai::Calendar::Service',
                       foreign_key: :ai_calendar_service_id, inverse_of: :appointment_services

  validates :ai_calendar_service_id, uniqueness: { scope: :ai_calendar_appointment_id }
end
