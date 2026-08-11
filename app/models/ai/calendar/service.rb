# What the business sells, entered once.
#
# `global` covers the common case where everyone performs it. When false, the
# join says who does — which is what lets the operator connect an employee's
# calendar and tick only the services that person actually delivers.
#
# Duration and buffer live here because the slot arithmetic is OURS. Left as
# prose in a knowledge document, the model would be adding 90 minutes to 14:00
# by itself, and it gets that wrong the same way it gets prices wrong.
class Ai::Calendar::Service < ApplicationRecord
  self.table_name = 'ai_calendar_services'

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account

  has_many :service_professionals, class_name: 'Ai::Calendar::ServiceProfessional',
                                   foreign_key: :ai_calendar_service_id, dependent: :destroy, inverse_of: :service
  has_many :professionals, through: :service_professionals
  # `:nullify`, which is why the column is nullable: retiring a service from the
  # menu must not erase the appointments already booked under it.
  has_many :appointments, class_name: 'Ai::Calendar::Appointment',
                          foreign_key: :ai_calendar_service_id, dependent: :nullify, inverse_of: :service

  validates :name, presence: true
  validates :duration_minutes, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 600 }
  validates :buffer_minutes, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 240 }
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :active, -> { where(active: true) }

  # What the chair is actually occupied for. The customer is told the duration;
  # the calendar is blocked for duration + buffer, so the next booking cannot
  # start while the room is still being turned around.
  def occupied_minutes
    duration_minutes + buffer_minutes.to_i
  end

  def push_event_data
    {
      id: id, name: name, duration_minutes: duration_minutes, price_cents: price_cents,
      buffer_minutes: buffer_minutes, global: global, active: active,
      professional_ids: global? ? [] : service_professionals.pluck(:ai_calendar_professional_id)
    }
  end
end
