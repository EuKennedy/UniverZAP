require 'rails_helper'

# The scheduling tables as one chain, because that is how they fail: an
# association named wrong loads fine on its own and blows up the first time the
# agent asks a professional what it can perform.
RSpec.describe 'Ai::Calendar' do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }

  let(:connection) do
    Ai::Calendar::Connection.create!(
      ai_assistant: assistant, account: account,
      google_email: 'salao@lizzon.com.br', encrypted_refresh_token: 'refresh-token'
    )
  end

  let(:professional) do
    Ai::Calendar::Professional.create!(
      connection: connection, ai_assistant: assistant, account: account,
      name: 'Agenda do salão', calendar_id: 'primary'
    )
  end

  def service(name:, global: true, duration: 90, buffer: 0)
    Ai::Calendar::Service.create!(
      ai_assistant: assistant, account: account, name: name,
      duration_minutes: duration, buffer_minutes: buffer, global: global
    )
  end

  describe 'what a professional can perform' do
    it 'offers every service the business marked as global' do
      service(name: 'Progressiva')

      expect(professional.services.map(&:name)).to eq(['Progressiva'])
    end

    # The reason `global` exists: connecting an employee's calendar and ticking
    # only what that person actually delivers.
    it 'ignores a non-global service nobody assigned to them' do
      service(name: 'Botox', global: false)

      expect(professional.services).to be_empty
    end

    it 'offers a non-global service once it is assigned to them' do
      botox = service(name: 'Botox', global: false)
      Ai::Calendar::ServiceProfessional.create!(service: botox, professional: professional)

      expect(professional.services.map(&:name)).to eq(['Botox'])
    end
  end

  # The chair is occupied for longer than the customer is told: the buffer is
  # what stops the next booking starting while the room is being turned around.
  it 'blocks the chair for the service duration plus its buffer' do
    expect(service(name: 'Progressiva', duration: 90, buffer: 15).occupied_minutes).to eq(105)
  end

  describe 'opening hours' do
    # One row per range, because a salon stops for lunch. A single opens/closes
    # pair per weekday would have the agent offering 12:30.
    it 'keeps two ranges on the same weekday' do
      Ai::Calendar::Hour.create!(professional: professional, account: account, weekday: 1,
                                 starts_at: '09:00', ends_at: '12:00')
      Ai::Calendar::Hour.create!(professional: professional, account: account, weekday: 1,
                                 starts_at: '13:30', ends_at: '19:00')

      expect(professional.hours_by_weekday[1].length).to eq(2)
    end

    # Produces no slots and no error otherwise, which reads as "the agent is
    # broken" rather than as a typo in the configuration.
    it 'refuses a range that ends before it starts' do
      hour = Ai::Calendar::Hour.new(professional: professional, account: account, weekday: 1,
                                    starts_at: '19:00', ends_at: '09:00')

      expect(hour).not_to be_valid
    end
  end

  describe 'what the agent may touch' do
    def appointment(assistant:, contact:, event_id:, starts_at: 2.days.from_now)
      Ai::Calendar::Appointment.create!(
        professional: professional, ai_assistant: assistant, account: account, contact: contact,
        google_event_id: event_id, starts_at: starts_at, ends_at: starts_at + 90.minutes
      )
    end

    let(:contact) { create(:contact, account: account) }

    it 'reaches the appointments it booked for this customer' do
      appointment(assistant: assistant, contact: contact, event_id: 'evt-1')

      expect(Ai::Calendar::Appointment.reachable_by(assistant, contact).map(&:google_event_id)).to eq(['evt-1'])
    end

    # The hard rule, at the appointment level: one workspace's agent must never
    # reach another's booking even if an id were crossed.
    it 'never reaches another customer, nor another agent' do
      other_contact = create(:contact, account: account)
      other_assistant = create(:ai_assistant, account: account)
      appointment(assistant: assistant, contact: other_contact, event_id: 'evt-outro-cliente')
      appointment(assistant: other_assistant, contact: contact, event_id: 'evt-outro-agente')

      expect(Ai::Calendar::Appointment.reachable_by(assistant, contact)).to be_empty
    end

    it 'leaves an appointment alone once it is inside the cancellation window' do
      appt = appointment(assistant: assistant, contact: contact, event_id: 'evt-2', starts_at: 2.hours.from_now)

      expect(appt).to be_within_cancellation_window(4)
    end
  end

  # Never sooner than the operator can be ready, never further out than they can
  # plan for.
  it 'offers only the window the settings allow' do
    setting = Ai::Calendar::Setting.create!(ai_assistant: assistant, account: account,
                                            minimum_lead_minutes: 120, horizon_days: 30)
    now = Time.current

    range = setting.bookable_range(now)

    expect(range.first).to be_within(1.second).of(now + 2.hours)
    expect(range.last).to be_within(1.second).of(now + 30.days)
  end
end
