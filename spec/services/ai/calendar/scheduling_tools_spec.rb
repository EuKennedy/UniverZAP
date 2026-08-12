require 'rails_helper'

RSpec.describe Ai::Calendar::SchedulingTools do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:other_contact) { create(:contact, account: account, name: 'Joana') }
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
  let!(:progressiva) do
    Ai::Calendar::Service.create!(ai_assistant_id: assistant.id, account_id: account.id,
                                  name: 'Progressiva sem formol', duration_minutes: 60, buffer_minutes: 0)
  end
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:wednesday) { zone.local(2026, 9, 2, 8, 0) }
  let(:google) { instance_double(Ai::Calendar::GoogleClient, busy: [], create_event: { 'id' => 'evt-1' }, delete_event: true) }
  let(:tools) { described_class.new(assistant: assistant, contact: contact, conversation: nil) }

  before do
    professional
    Ai::Calendar::Setting.create!(
      ai_assistant_id: assistant.id, account_id: account.id,
      minimum_lead_minutes: 0, horizon_days: 30, cancellation_window_hours: 2
    )
    professional.hours.create!(account_id: account.id, weekday: 3, starts_at: '09:00', ends_at: '12:00')
    allow(Ai::Calendar::GoogleClient).to receive(:new).and_return(google)
  end

  def parsed(result)
    JSON.parse(result)
  end

  describe 'the schemas' do
    it 'names the operator services so the model never invents one' do
      definitions = Ai::Calendar::ToolDefinitions.for(assistant)

      expect(definitions.map { |d| d[:name] })
        .to eq(%w[consultar_horarios agendar meus_agendamentos remarcar desmarcar])
      expect(definitions.first[:input_schema][:properties][:servicos][:description]).to include('Progressiva sem formol')
    end

    # A model holding a booking tool it cannot fulfil promises a time anyway.
    it 'offers nothing when there is no service to book' do
      progressiva.update!(active: false)

      expect(Ai::Calendar::ToolDefinitions.for(assistant)).to be_nil
    end
  end

  describe 'consultar_horarios' do
    it 'answers with real free slots' do
      travel_to(wednesday) do
        body = parsed(tools.call('consultar_horarios', { 'servicos' => ['progressiva'], 'data' => '2026-09-02' }))

        expect(body['horarios']).to include('2026-09-02T09:00')
        expect(body['duracao_minutos']).to eq(60)
      end
    end

    # The customer says "progressiva", the operator typed "Progressiva sem formol".
    it 'matches the service without accents or case' do
      travel_to(wednesday) do
        body = parsed(tools.call('consultar_horarios', { 'servicos' => ['PROGRESSIVA'] }))

        expect(body['horarios']).to be_present
      end
    end

    it 'says it did not recognise a service instead of guessing one' do
      travel_to(wednesday) do
        body = parsed(tools.call('consultar_horarios', { 'servicos' => ['botox capilar'] }))

        expect(body['error']).to be(true)
      end
    end

    it 'does not count as a write' do
      travel_to(wednesday) do
        tools.call('consultar_horarios', { 'servicos' => ['progressiva'] })

        expect(tools).not_to be_performed_write
      end
    end
  end

  describe 'agendar' do
    it 'books and reports the time back in the agenda own zone' do
      travel_to(wednesday) do
        body = parsed(tools.call('agendar', { 'servicos' => ['progressiva'], 'inicio' => '2026-09-02T09:00' }))

        expect(body['agendado']).to be(true)
        expect(body['inicio']).to eq('2026-09-02T09:00')
      end
    end

    # A retried turn must not book the same customer twice.
    it 'marks the turn as written even when the booking fails' do
      allow(google).to receive(:create_event).and_raise(Ai::Calendar::GoogleClient::Error, 'boom')

      travel_to(wednesday) do
        tools.call('agendar', { 'servicos' => ['progressiva'], 'inicio' => '2026-09-02T09:00' })

        expect(tools).to be_performed_write
      end
    end

    it 'tells the model to offer another time when the slot was just taken' do
      allow(google).to receive(:busy).and_return([zone.local(2026, 9, 2, 9, 0)..zone.local(2026, 9, 2, 10, 0)])

      travel_to(wednesday) do
        body = parsed(tools.call('agendar', { 'servicos' => ['progressiva'], 'inicio' => '2026-09-02T09:00' }))

        expect(body['error']).to be(true)
        expect(body['message']).to include('ocupado')
      end
    end
  end

  describe 'meus_agendamentos, remarcar and desmarcar' do
    def booked_for(who, starts_at)
      Ai::Calendar::Appointment.create!(
        ai_calendar_professional_id: professional.id, ai_assistant_id: assistant.id,
        account_id: account.id, contact_id: who.id, google_event_id: "evt-#{who.id}",
        starts_at: starts_at, ends_at: starts_at + 1.hour, status: 'booked'
      )
    end

    it 'lists only this customer appointments' do
      travel_to(wednesday) do
        booked_for(contact, zone.local(2026, 9, 4, 10, 0))
        booked_for(other_contact, zone.local(2026, 9, 4, 11, 0))

        body = parsed(tools.call('meus_agendamentos', {}))

        expect(body['agendamentos'].size).to eq(1)
      end
    end

    # The boundary that keeps one customer out of another's agenda even with a
    # guessed id.
    it 'refuses to touch an appointment belonging to somebody else' do
      travel_to(wednesday) do
        theirs = booked_for(other_contact, zone.local(2026, 9, 4, 11, 0))

        body = parsed(tools.call('desmarcar', { 'agendamento_id' => theirs.id }))

        expect(body['error']).to be(true)
        expect(theirs.reload.status).to eq('booked')
      end
    end

    it 'cancels this customer own appointment' do
      travel_to(wednesday) do
        mine = booked_for(contact, zone.local(2026, 9, 4, 10, 0))

        expect(parsed(tools.call('desmarcar', { 'agendamento_id' => mine.id }))['desmarcado']).to be(true)
        expect(mine.reload.status).to eq('cancelled')
      end
    end

    it 'hands over to a human inside the cancellation window' do
      travel_to(wednesday) do
        soon = booked_for(contact, wednesday + 1.hour)

        body = parsed(tools.call('desmarcar', { 'agendamento_id' => soon.id }))

        expect(body['error']).to be(true)
        expect(body['message']).to include('equipe')
      end
    end
  end

  # The operator disconnected the calendar. The agent must stop offering times
  # rather than apologise forever.
  it 'tells the model to stop offering times when the grant is gone' do
    allow(google).to receive(:busy).and_raise(Ai::Calendar::GoogleClient::Revoked, 'revoked')

    travel_to(wednesday) do
      body = parsed(tools.call('consultar_horarios', { 'servicos' => ['progressiva'] }))

      expect(body['error']).to be(true)
      expect(body['message']).to include('desconectada')
    end
  end

  it 'reports an unknown tool as data instead of raising' do
    expect(parsed(tools.call('inventada', {}))['error']).to be(true)
  end
end
