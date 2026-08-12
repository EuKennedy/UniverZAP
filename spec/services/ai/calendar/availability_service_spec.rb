require 'rails_helper'

RSpec.describe Ai::Calendar::AvailabilityService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:connection) do
    Ai::Calendar::Connection.create!(
      ai_assistant: assistant, account: account, google_email: 'salao@gmail.com', encrypted_refresh_token: 'rt'
    )
  end
  let(:professional) do
    connection.professionals.create!(
      ai_assistant_id: assistant.id, account_id: account.id,
      name: 'Agenda do salão', calendar_id: 'primary', timezone: 'America/Sao_Paulo'
    )
  end
  let(:service) do
    Ai::Calendar::Service.create!(
      ai_assistant_id: assistant.id, account_id: account.id,
      name: 'Progressiva', duration_minutes: 60, buffer_minutes: 0
    )
  end
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  # A Wednesday, so the weekday arithmetic is never accidentally right.
  let(:wednesday) { zone.local(2026, 9, 2, 8, 0) }
  let(:google) { instance_double(Ai::Calendar::GoogleClient, busy: []) }

  before do
    Ai::Calendar::Setting.create!(
      ai_assistant_id: assistant.id, account_id: account.id,
      minimum_lead_minutes: 0, horizon_days: 7, cancellation_window_hours: 2
    )
    allow(Ai::Calendar::GoogleClient).to receive(:new).and_return(google)
  end

  def open_on(weekday, from, to)
    professional.hours.create!(account_id: account.id, weekday: weekday, starts_at: from, ends_at: to)
  end

  def slots(**args)
    described_class.new(assistant: assistant, service: service, professional: professional, **args).perform
  end

  it 'offers nothing on a day the business is closed' do
    open_on(4, '09:00', '12:00') # thursday only

    travel_to(wednesday) do
      expect(slots(to: wednesday.end_of_day)).to be_empty
    end
  end

  it 'offers the quarter hours that fit inside the opening range' do
    open_on(3, '09:00', '11:00')

    travel_to(wednesday) do
      times = slots(to: wednesday.end_of_day).map { |slot| slot.strftime('%H:%M') }
      expect(times).to eq(%w[09:00 09:15 09:30 09:45 10:00])
    end
  end

  # The chair has to be free for the WHOLE service before closing time.
  it 'never offers a slot the service cannot finish inside' do
    open_on(3, '09:00', '10:00')

    travel_to(wednesday) do
      expect(slots(to: wednesday.end_of_day).map { |slot| slot.strftime('%H:%M') }).to eq(['09:00'])
    end
  end

  # The lunch break is a real gap because the week is stored as ranges.
  it 'skips the lunch break instead of offering 12:30' do
    open_on(3, '09:00', '10:00')
    open_on(3, '13:00', '14:00')

    travel_to(wednesday) do
      expect(slots(to: wednesday.end_of_day).map { |slot| slot.strftime('%H:%M') }).to eq(%w[09:00 13:00])
    end
  end

  # This is why we ask Google rather than only subtracting our own rows: the
  # dentist the owner typed in by hand has to block the chair too.
  it 'drops slots Google reports as busy, whoever put them there' do
    open_on(3, '09:00', '12:00')
    allow(google).to receive(:busy).and_return([zone.local(2026, 9, 2, 9, 30)..zone.local(2026, 9, 2, 10, 30)])

    travel_to(wednesday) do
      times = slots(to: wednesday.end_of_day).map { |slot| slot.strftime('%H:%M') }
      expect(times).to eq(%w[10:30 10:45 11:00])
    end
  end

  # The buffer is invisible to the customer and decisive for the agenda.
  it 'holds the chair for duration plus buffer' do
    service.update!(duration_minutes: 60, buffer_minutes: 30)
    open_on(3, '09:00', '10:30')

    travel_to(wednesday) do
      expect(slots(to: wednesday.end_of_day).map { |slot| slot.strftime('%H:%M') }).to eq(['09:00'])
    end
  end

  # Somebody booking for twenty minutes from now finds nobody ready.
  it 'refuses anything sooner than the minimum notice' do
    assistant.calendar_setting.update!(minimum_lead_minutes: 120)
    open_on(3, '09:00', '12:00')

    travel_to(wednesday) do
      expect(slots(to: wednesday.end_of_day).map { |slot| slot.strftime('%H:%M') }).to eq(%w[10:00 10:15 10:30 10:45 11:00])
    end
  end

  it 'refuses anything past the horizon the operator set' do
    assistant.calendar_setting.update!(horizon_days: 1)
    open_on(3, '09:00', '10:00')
    open_on(5, '09:00', '10:00') # friday, two days out

    travel_to(wednesday) do
      expect(slots.map(&:to_date).uniq).to eq([wednesday.to_date])
    end
  end

  it 'returns nothing rather than guessing when Google cannot be reached' do
    open_on(3, '09:00', '12:00')
    allow(google).to receive(:busy).and_raise(Ai::Calendar::GoogleClient::Error, 'boom')

    travel_to(wednesday) do
      expect { slots(to: wednesday.end_of_day) }.to raise_error(Ai::Calendar::GoogleClient::Error)
    end
  end

  it 'answers in the agenda own timezone, not the server one' do
    open_on(3, '09:00', '10:00')

    travel_to(wednesday) do
      expect(slots(to: wednesday.end_of_day).first.time_zone.name).to eq('America/Sao_Paulo')
    end
  end
end
