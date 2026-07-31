require 'rails_helper'

RSpec.describe Ai::Belezaki::SchedulingTools do
  describe '.definitions' do
    it 'exposes the booking tool only when booking is allowed' do
      with_booking = described_class.definitions(include_booking: true).map { |t| t[:name] }
      without_booking = described_class.definitions(include_booking: false).map { |t| t[:name] }

      expect(with_booking).to include('agendar')
      expect(without_booking).not_to include('agendar')
      expect(without_booking).to include('listar_servicos', 'consultar_horarios')
    end
  end

  describe '#call' do
    let(:client) { instance_double(Ai::Belezaki::AgentClient) }

    def tools
      described_class.new(client, scope: 'conv-1')
    end

    def booking_input(overrides = {})
      {
        'service_id' => 's1', 'start' => '2026-06-20T16:00:00-03:00',
        'client_name' => 'Ana', 'client_phone' => '+5531999999999'
      }.merge(overrides)
    end

    it 'returns the service list as a JSON string' do
      allow(client).to receive(:services).and_return({ 'services' => [] })

      expect(tools.call('listar_servicos', {})).to eq('{"services":[]}')
    end

    it 'maps agendar to create_appointment with an action-scoped idempotency key' do
      allow(client).to receive(:create_appointment).and_return({ 'appointment' => { 'id' => 'a1' } })

      tools.call('agendar', booking_input)

      expect(client).to have_received(:create_appointment)
        .with(hash_including(service_id: 's1', idempotency_key: a_string_starting_with('conv-1:')))
    end

    it 'reuses the SAME idempotency key when the same slot is re-booked (dedups duplicates)' do
      keys = []
      allow(client).to receive(:create_appointment) do |**kwargs|
        keys << kwargs[:idempotency_key]
        { 'appointment' => { 'id' => 'a1' } }
      end

      tools.call('agendar', booking_input)
      tools.call('agendar', booking_input)

      expect(keys.uniq.size).to eq(1)
    end

    it 'uses DIFFERENT keys for two distinct bookings so both go through' do
      keys = []
      allow(client).to receive(:create_appointment) do |**kwargs|
        keys << kwargs[:idempotency_key]
        { 'appointment' => { 'id' => 'a1' } }
      end

      tools.call('agendar', booking_input('start' => '2026-06-20T16:00:00-03:00'))
      tools.call('agendar', booking_input('start' => '2026-06-21T10:00:00-03:00'))

      expect(keys.uniq.size).to eq(2)
    end

    it 'prefers the contact record name/phone over the LLM-extracted input' do
      captured = nil
      allow(client).to receive(:create_appointment) do |**kwargs|
        captured = kwargs
        { 'appointment' => { 'id' => 'a1' } }
      end
      contact_tools = described_class.new(client, scope: 'conv-1', contact: { name: 'Ana Real', phone: '+5531988887777' })

      contact_tools.call('agendar', booking_input('client_name' => 'nome errado', 'client_phone' => '+550000000000'))

      expect(captured[:client]).to eq({ name: 'Ana Real', phone: '+5531988887777' })
    end

    it 'falls back to the LLM input when the contact has no name/phone on file' do
      captured = nil
      allow(client).to receive(:create_appointment) do |**kwargs|
        captured = kwargs
        { 'appointment' => { 'id' => 'a1' } }
      end

      tools.call('agendar', booking_input('client_name' => 'Bia', 'client_phone' => '+5531977776666'))

      expect(captured[:client]).to eq({ name: 'Bia', phone: '+5531977776666' })
    end

    it 'returns belezaki errors as data instead of raising' do
      allow(client).to receive(:services).and_raise(Ai::Belezaki::AgentClient::Error, 'boom')

      expect(tools.call('listar_servicos', {})).to include('belezaki_error')
    end
  end
end
