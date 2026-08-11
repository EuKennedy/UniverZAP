# Who performs a service that is not offered by everyone. Only ever written for
# services with `global: false`.
class Ai::Calendar::ServiceProfessional < ApplicationRecord
  self.table_name = 'ai_calendar_service_professionals'

  belongs_to :service, class_name: 'Ai::Calendar::Service',
                       foreign_key: :ai_calendar_service_id, inverse_of: :service_professionals
  belongs_to :professional, class_name: 'Ai::Calendar::Professional',
                            foreign_key: :ai_calendar_professional_id, inverse_of: :service_professionals

  validates :ai_calendar_service_id, uniqueness: { scope: :ai_calendar_professional_id }
end
