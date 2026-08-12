require 'rails_helper'

RSpec.describe Ai::Calendar::BookService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999999999') }
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
  let(:progressiva) do
    Ai::Calendar::Service.create!(ai_assistant_id: assistant.id, account_id: account.id,
                                  name: 'Progressiva', duration_minutes: 90, buffer_minutes: 15)
  end
  let(:corte) do
    Ai::Calendar::Service.create!(ai_assistant_id: assistant.id, account_id: account.id,
                                  name: 'Corte', duration_minutes: 30, buffer_minutes: 10)
  end
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:starts_at) { zone.local(2026, 9, 3, 14, 0) }
  let(:google) { instance_double(Ai::Calendar::GoogleClient, busy: [], create_event: { 'id' => 'evt-1' }) }

  before do
    professional
    allow(Ai::Calendar::GoogleClient).to receive(:new).and_return(google)
  end

  def book(services)
    described_class.new(assistant: assistant, contact: contact, services: services, starts_at: starts_at).perform
  end

  it 'writes the event first and keeps our row pointing at it' do
    appointment = book([progressiva])

    expect(appointment.google_event_id).to eq('evt-1')
    expect(appointment.status).to eq('booked')
    expect(appointment.services).to eq([progressiva])
  end

  # The operator's call: two services are ONE block, durations summed.
  it 'books a combo as a single block with the durations summed' do
    appointment = book([progressiva, corte])

    expect(appointment.services).to contain_exactly(progressiva, corte)
    # 90 + 30, plus the largest buffer applied once at the end.
    expect(((appointment.ends_at - appointment.starts_at) / 60).round).to eq(135)
  end

  it 'applies the buffer once, at the end, not between each service' do
    appointment = book([progressiva, corte])
    naive_sum = progressiva.occupied_minutes + corte.occupied_minutes

    expect(((appointment.ends_at - appointment.starts_at) / 60).round).to be < naive_sum
  end

  # Between the agent saying "14h está livre" and the customer saying "pode ser"
  # the owner books somebody from their phone, and Google has no insert-if-free.
  it 'asks free/busy again immediately before writing' do
    allow(google).to receive(:busy).and_return([starts_at..(starts_at + 1.hour)])

    expect { book([progressiva]) }.to raise_error(described_class::Unavailable)
    expect(google).not_to have_received(:create_event)
  end

  it 'refuses to book nothing' do
    expect { book([]) }.to raise_error(described_class::NothingToBook)
  end

  # The month view on a phone is where the owner actually reads this.
  it 'puts the service and the customer in the title, the rest in the description' do
    book([progressiva])

    expect(google).to have_received(:create_event) do |args|
      expect(args[:payload][:summary]).to eq('Progressiva · Maria Silva')
      expect(args[:payload][:description]).to include('+5511999999999')
      expect(args[:payload][:description]).to include('Profissional: Ana')
      expect(args[:payload][:start][:timeZone]).to eq('America/Sao_Paulo')
    end
  end

  it 'does not leave a row behind when Google refuses the event' do
    allow(google).to receive(:create_event).and_raise(Ai::Calendar::GoogleClient::Error, 'boom')

    expect { book([progressiva]) }.to raise_error(Ai::Calendar::GoogleClient::Error)
    expect(Ai::Calendar::Appointment.count).to eq(0)
  end
end
