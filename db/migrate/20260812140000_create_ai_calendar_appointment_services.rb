# One appointment, several services.
#
# The operator's call: "progressiva + corte" is ONE block on the agenda with
# the durations summed, not two bookings the customer has to keep track of.
# That makes the single service_id on the appointment a lie, so the truth moves
# to a join and the old column is dropped rather than left as a second answer
# to the same question.
#
# Nothing is migrated across because nothing has been booked yet: the tables
# that this replaces have never had a row in them.
class CreateAiCalendarAppointmentServices < ActiveRecord::Migration[7.1]
  def up
    create_table :ai_calendar_appointment_services do |t|
      t.references :ai_calendar_appointment, null: false, foreign_key: true, index: false
      t.references :ai_calendar_service, null: false, foreign_key: true, index: false
      t.timestamps
    end
    add_index :ai_calendar_appointment_services,
              %i[ai_calendar_appointment_id ai_calendar_service_id],
              unique: true, name: 'idx_calendar_appt_service'
    add_index :ai_calendar_appointment_services, :ai_calendar_service_id, name: 'idx_calendar_appt_service_on_service'

    remove_column :ai_calendar_appointments, :ai_calendar_service_id
  end

  def down
    add_reference :ai_calendar_appointments, :ai_calendar_service, null: true, foreign_key: true, index: false
    drop_table :ai_calendar_appointment_services
  end
end
