# The scheduling module, independent of any third-party salon system: the agent
# reads availability straight from the operator's own Google Calendar and books
# into it.
#
# Everything hangs off PROFESSIONAL, even though the MVP shows one and never
# says the word. A salon that grows to three chairs then costs an INSERT rather
# than a migration, and "tem horário às 15h?" keeps a defined answer — it means
# "with whom", and that question has to be answerable from day one.
#
# `account_id` is repeated on every table even where it is reachable through the
# assistant. It is the column every scope filters on, and one crossed id here
# would book a customer into another business's calendar.
class CreateAiCalendarTables < ActiveRecord::Migration[7.1]
  def change
    create_connections
    create_professionals
    create_services
    create_service_professionals
    create_hours
    create_appointments
    create_settings
  end

  private

  # One OAuth grant to a Google account. Per ASSISTANT, not per account: an
  # operator may run three agents that are three different businesses — a
  # clinic, a salon, something else — each with its own calendar.
  def create_connections
    create_table :ai_calendar_connections do |t|
      t.references :ai_assistant, null: false, foreign_key: true, index: false
      t.references :account, null: false, foreign_key: true, index: false
      t.string :google_email, null: false
      # Only the refresh token is kept. Access tokens live an hour and are
      # fetched on demand; storing them would mean storing something stale.
      t.text :encrypted_refresh_token, null: false
      # 'active' | 'revoked'. A revoked grant must stop the agent rather than
      # let it promise appointments it cannot make.
      t.string :status, null: false, default: 'active'
      t.datetime :last_error_at
      t.string :last_error
      t.timestamps
    end
    add_index :ai_calendar_connections, %i[ai_assistant_id status]
    add_index :ai_calendar_connections, %i[account_id]
  end

  # A person with an agenda. In practice: one Google CALENDAR, which is why the
  # calendar_id lives here and not on the connection — one Google account holds
  # several calendars, so three professionals can share a single grant.
  #
  # The timezone is the calendar's own, deliberately: what the owner reads on
  # their screen is what the customer must hear.
  def create_professionals
    create_table :ai_calendar_professionals do |t|
      t.references :ai_calendar_connection, null: false, foreign_key: true, index: false
      t.references :ai_assistant, null: false, foreign_key: true, index: false
      t.references :account, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.string :calendar_id, null: false
      t.string :timezone, null: false, default: 'America/Sao_Paulo'
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :ai_calendar_professionals, %i[ai_assistant_id active]
    add_index :ai_calendar_professionals, %i[ai_calendar_connection_id calendar_id],
              unique: true, name: 'idx_calendar_pro_on_conn_calendar'
  end

  # Of the BUSINESS, not of the person: "progressiva, 90min, R$ 219" is entered
  # once. `global` covers the common case where everyone performs it; when it is
  # false the join table below says who does.
  #
  # Duration and buffer are what make the slot arithmetic OURS. Left as prose in
  # a knowledge document, the model would be adding 90 minutes to 14:00 by
  # itself, and it gets that wrong the same way it gets prices wrong.
  def create_services
    create_table :ai_calendar_services do |t|
      t.references :ai_assistant, null: false, foreign_key: true, index: false
      t.references :account, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.integer :duration_minutes, null: false
      t.integer :price_cents
      # Time the chair needs before the next customer: cleaning, receiving,
      # breathing. Without it the agent books 14:00 and 15:00 back to back.
      t.integer :buffer_minutes, null: false, default: 0
      t.boolean :global, null: false, default: true
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :ai_calendar_services, %i[ai_assistant_id active]
  end

  # Only ever written for services with `global: false`.
  def create_service_professionals
    create_table :ai_calendar_service_professionals do |t|
      t.references :ai_calendar_service, null: false, foreign_key: true, index: false
      t.references :ai_calendar_professional, null: false, foreign_key: true, index: false
      t.timestamps
    end
    add_index :ai_calendar_service_professionals, %i[ai_calendar_service_id ai_calendar_professional_id],
              unique: true, name: 'idx_calendar_service_pro'
    add_index :ai_calendar_service_professionals, :ai_calendar_professional_id, name: 'idx_calendar_service_pro_on_pro'
  end

  # One row per RANGE, not per day, because a salon stops for lunch. A single
  # opens/closes pair per weekday would have the agent booking 12:30.
  def create_hours
    create_table :ai_calendar_hours do |t|
      t.references :ai_calendar_professional, null: false, foreign_key: true, index: false
      t.references :account, null: false, foreign_key: true, index: false
      # 0 = Sunday, matching Ruby's Date#wday, so nothing has to translate.
      t.integer :weekday, null: false
      t.time :starts_at, null: false
      t.time :ends_at, null: false
      t.timestamps
    end
    add_index :ai_calendar_hours, %i[ai_calendar_professional_id weekday], name: 'idx_calendar_hours_on_pro_weekday'
  end

  # Our index of what WE booked — not a mirror of the calendar. Google stays the
  # single source of truth for availability, because the owner books from their
  # phone without passing through us and any copy would be born wrong.
  #
  # This exists because rescheduling and cancelling need to answer "which event
  # belongs to this customer", which Google cannot. It is also the boundary that
  # keeps the agent off appointments it did not create: the dentist, the lunch,
  # anything the owner put there by hand.
  def create_appointments
    create_table :ai_calendar_appointments do |t|
      t.references :ai_calendar_professional, null: false, foreign_key: true, index: false
      t.references :ai_calendar_service, null: true, foreign_key: true, index: false
      t.references :ai_assistant, null: false, foreign_key: true, index: false
      t.references :account, null: false, foreign_key: true, index: false
      t.references :contact, null: false, foreign_key: true, index: false
      t.references :conversation, null: true, foreign_key: true, index: false
      t.string :google_event_id, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      # 'booked' | 'cancelled'. Kept after cancellation so the agent can say
      # "you had one on Thursday and it was cancelled" instead of drawing a
      # blank.
      t.string :status, null: false, default: 'booked'
      t.timestamps
    end
    add_index :ai_calendar_appointments, %i[contact_id status], name: 'idx_calendar_appt_on_contact_status'
    add_index :ai_calendar_appointments, %i[ai_calendar_professional_id starts_at], name: 'idx_calendar_appt_on_pro_start'
    add_index :ai_calendar_appointments, :google_event_id, unique: true, name: 'idx_calendar_appt_on_event'
  end

  # The rules that decide what the agent may offer, one row per assistant.
  # Every one of these is here because its absence is felt in the first week of
  # real use rather than in a demo.
  def create_settings
    create_table :ai_calendar_settings do |t|
      t.references :ai_assistant, null: false, foreign_key: true, index: { unique: true }
      t.references :account, null: false, foreign_key: true, index: false
      # Nothing sooner than this: a customer booking for 20 minutes from now
      # finds nobody ready.
      t.integer :minimum_lead_minutes, null: false, default: 120
      # And nothing further out than this, or somebody books for March.
      t.integer :horizon_days, null: false, default: 60
      # Past this the agent stops touching an appointment and explains it is too
      # close to the time — it protects the professional from an automated
      # last-minute no-show.
      t.integer :cancellation_window_hours, null: false, default: 4
      t.timestamps
    end
  end
end
