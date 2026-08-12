require 'rails_helper'

RSpec.describe Ai::Calendar::ChangeService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:connection) do
    Ai::Calendar::Connection.create!(
      ai_assistant: assistant, account: account, google_email: 'salao@gmail.com', encrypted_refresh_token: 'rt'
    )
  end
  let(:professional) do
    connection.professionals.create!(
      ai_assistant_id: assistant.id, account_id: account.id,
      name: 'Ana', calendar_id: 'primary', timezone: 'America/Sao_Paulo'
    )
  end
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:now) { zone.local(2026, 9, 1, 9, 0) }
  let(:google) { instance_double(Ai::Calendar::GoogleClient, busy: [], update_event: {}, delete_event: true) }

  # Far enough out that the two-hour window is not what is being tested.
  def appointment_at(starts_at)
    Ai::Calendar::Appointment.create!(
      ai_calendar_professional_id: professional.id, ai_assistant_id: assistant.id,
      account_id: account.id, contact_id: contact.id, google_event_id: 'evt-1',
      starts_at: starts_at, ends_at: starts_at + 1.hour, status: 'booked'
    )
  end

  before do
    Ai::Calendar::Setting.create!(
      ai_assistant_id: assistant.id, account_id: account.id,
      minimum_lead_minutes: 0, horizon_days: 60, cancellation_window_hours: 2
    )
    allow(Ai::Calendar::GoogleClient).to receive(:new).and_return(google)
  end

  describe '#reschedule' do
    it 'moves the event and our row together' do
      travel_to(now) do
        appointment = appointment_at(zone.local(2026, 9, 3, 14, 0))
        moved = described_class.new(appointment: appointment).reschedule(zone.local(2026, 9, 4, 10, 0))

        expect(moved.starts_at).to eq(zone.local(2026, 9, 4, 10, 0))
        expect(google).to have_received(:update_event)
      end
    end

    # Moving must not silently make the appointment longer than what the
    # customer agreed to, even if the service was re-timed since.
    it 'keeps the original duration' do
      travel_to(now) do
        appointment = appointment_at(zone.local(2026, 9, 3, 14, 0))
        moved = described_class.new(appointment: appointment).reschedule(zone.local(2026, 9, 4, 10, 0))

        expect(((moved.ends_at - moved.starts_at) / 60).round).to eq(60)
      end
    end

    it 'refuses to land on top of something else' do
      travel_to(now) do
        appointment = appointment_at(zone.local(2026, 9, 3, 14, 0))
        allow(google).to receive(:busy).and_return([zone.local(2026, 9, 4, 10, 30)..zone.local(2026, 9, 4, 11, 30)])

        expect { described_class.new(appointment: appointment).reschedule(zone.local(2026, 9, 4, 10, 0)) }
          .to raise_error(described_class::Unavailable)
      end
    end

    # Its own current booking is not a conflict with itself.
    it 'does not treat the appointment being moved as a conflict' do
      travel_to(now) do
        appointment = appointment_at(zone.local(2026, 9, 4, 10, 0))
        allow(google).to receive(:busy).and_return([appointment.starts_at..appointment.ends_at])

        expect { described_class.new(appointment: appointment).reschedule(zone.local(2026, 9, 4, 10, 0)) }
          .not_to raise_error
      end
    end
  end

  describe '#cancel' do
    it 'removes the event and keeps the row marked cancelled' do
      travel_to(now) do
        appointment = appointment_at(zone.local(2026, 9, 3, 14, 0))
        described_class.new(appointment: appointment).cancel

        expect(appointment.reload.status).to eq('cancelled')
        expect(google).to have_received(:delete_event)
      end
    end

    # Kept rather than deleted so the agent can answer "you had one on Thursday
    # and it was cancelled" instead of drawing a blank.
    it 'does not delete our row' do
      travel_to(now) do
        appointment = appointment_at(zone.local(2026, 9, 3, 14, 0))
        described_class.new(appointment: appointment).cancel

        expect(Ai::Calendar::Appointment.exists?(appointment.id)).to be(true)
      end
    end
  end

  # The operator's number: past it a human decides, because an automated
  # no-show an hour before is a chair nobody could have refilled.
  describe 'inside the cancellation window' do
    it 'refuses to cancel' do
      travel_to(now) do
        appointment = appointment_at(now + 1.hour)

        expect { described_class.new(appointment: appointment).cancel }.to raise_error(described_class::TooLate)
        expect(google).not_to have_received(:delete_event)
      end
    end

    it 'refuses to reschedule' do
      travel_to(now) do
        appointment = appointment_at(now + 1.hour)

        expect { described_class.new(appointment: appointment).reschedule(now + 5.hours) }
          .to raise_error(described_class::TooLate)
      end
    end

    it 'allows it just outside the window' do
      travel_to(now) do
        appointment = appointment_at(now + 3.hours)

        expect { described_class.new(appointment: appointment).cancel }.not_to raise_error
      end
    end
  end
end
