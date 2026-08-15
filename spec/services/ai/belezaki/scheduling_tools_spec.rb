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

    it 'reports no external write before any booking is attempted' do
      allow(client).to receive(:services).and_return({ 'services' => [] })
      executor = tools

      executor.call('listar_servicos', {})

      expect(executor.performed_write?).to be(false)
    end

    it 'flags the external write even when the booking call blows up mid-flight' do
      allow(client).to receive(:create_appointment).and_raise(Ai::Belezaki::AgentClient::Error, 'timeout')
      executor = tools

      executor.call('agendar', booking_input)

      expect(executor.performed_write?).to be(true)
    end

    it 'returns belezaki errors as data instead of raising' do
      allow(client).to receive(:services).and_raise(Ai::Belezaki::AgentClient::Error, 'boom')

      expect(tools.call('listar_servicos', {})).to include('Não consegui falar com a agenda')
    end

    describe 'what the model is told when the salon refuses' do
      def raising(error)
        allow(client).to receive(:availability).and_raise(error)
        JSON.parse(tools.call('consultar_horarios', { 'service_id' => 's1', 'date' => '2026-06-20' }))
      end

      # A taken slot is a normal turn in a booking conversation, not a failure —
      # but only if the code survives the executor.
      it 'keeps the code so a taken slot is not just an error' do
        body = raising(Ai::Belezaki::AgentClient::Error.new('Horário não está mais disponível.', code: 'slot_taken'))

        expect(body['error']).to eq('slot_taken')
        expect(body['message']).to include('Consulte os horários de novo')
      end

      # Their validation strings are an English array written for us. The
      # customer must never see one.
      it 'never passes the salon own words through' do
        error = Ai::Belezaki::AgentClient::Error.new(
          'Dados inválidos.', code: 'validation_failed', validation: ['idempotency_key must be longer']
        )
        body = raising(error)

        expect(body['message']).not_to include('idempotency_key')
      end

      # Left as a bare fact, the model fills the gap with "volto já já" — a
      # follow-up it has no turn to perform.
      it 'tells the agent to stop offering times when the agenda is unreachable' do
        body = raising(Ai::Belezaki::AgentClient::Error.new('boom', code: 'http_503'))

        expect(body['message']).to include('não ofereça horário')
      end
    end

    describe 'moving and cancelling what the customer already has' do
      let(:with_contact) { described_class.new(client, scope: 'conv-1', contact: { name: 'Ana', phone: '+5531999999999' }) }

      # The phone IS the scope: the salon answers 404 for anything belonging to
      # somebody else. Taking it from the chat text would let a mistyped digit
      # hand this customer another person's agenda.
      it 'looks the customer up by the contact record, never by the model input' do
        allow(client).to receive(:appointments).and_return({ 'appointments' => [] })

        with_contact.call('meus_agendamentos', { 'phone' => '+5531000000000' })

        expect(client).to have_received(:appointments).with(phone: '+5531999999999')
      end

      it 'asks for the number instead of querying without one' do
        expect(client).not_to receive(:appointments)

        expect(tools.call('meus_agendamentos', {})).to include('invalid_input')
      end

      # The turn guard reads a move off "remarcado". belezaki answers
      # {"appointment": ..., "changed": true}, which matches nothing.
      it 'says remarcado when the salon moved it' do
        allow(client).to receive(:reschedule_appointment).and_return(
          'appointment' => { 'start' => '2027-03-16T14:00:00-03:00' }, 'changed' => true
        )

        body = JSON.parse(with_contact.call('remarcar', { 'appointment_id' => 'a1',
                                                          'start' => '2027-03-16T14:00:00-03:00' }))

        expect(body['remarcado']).to be(true)
        expect(body['quando']).to eq('2027-03-16T14:00:00-03:00')
      end

      # `changed: false` means it was ALREADY at that time. That is the outcome
      # the customer asked for, and it is what makes a retry safe without a key.
      it 'treats an unchanged appointment as success' do
        allow(client).to receive(:reschedule_appointment).and_return(
          'appointment' => { 'start' => '2027-03-16T14:00:00-03:00' }, 'changed' => false
        )

        body = JSON.parse(with_contact.call('remarcar', { 'appointment_id' => 'a1',
                                                          'start' => '2027-03-16T14:00:00-03:00' }))

        expect(body['remarcado']).to be(true)
      end

      it 'says desmarcado when the salon cancelled it' do
        allow(client).to receive(:cancel_appointment).and_return('changed' => true)

        body = JSON.parse(with_contact.call('desmarcar', { 'appointment_id' => 'a1' }))

        expect(body['desmarcado']).to be(true)
      end

      it 'sends the contact phone and the reason on a cancellation' do
        allow(client).to receive(:cancel_appointment).and_return('changed' => true)

        with_contact.call('desmarcar', { 'appointment_id' => 'a1', 'reason' => 'imprevisto' })

        expect(client).to have_received(:cancel_appointment)
          .with('a1', hash_including(client_phone: '+5531999999999', reason: 'imprevisto'))
      end

      # Too close to the appointment is the salon's rule, and the agent has to
      # hand over rather than argue about it with the customer.
      it 'tells the agent to hand over when the notice window closed' do
        allow(client).to receive(:cancel_appointment)
          .and_raise(Ai::Belezaki::AgentClient::Error.new('x', code: 'notice_window_closed'))

        body = JSON.parse(with_contact.call('desmarcar', { 'appointment_id' => 'a1' }))

        expect(body['error']).to eq('notice_window_closed')
        expect(body['message']).to include('equipe vai confirmar')
      end

      # A move that timed out may still have landed, so the turn must not replay.
      it 'marks the turn as written even when the move fails' do
        allow(client).to receive(:reschedule_appointment).and_raise(Ai::Belezaki::AgentClient::Error, 'timeout')
        executor = with_contact

        executor.call('remarcar', { 'appointment_id' => 'a1', 'start' => '2027-03-16T14:00:00-03:00' })

        expect(executor.performed_write?).to be(true)
      end
    end

    describe 'the till record' do
      let(:with_contact) { described_class.new(client, scope: 'conv-1', contact: { name: 'Ana', phone: '+5531999999999' }) }

      # The salon answers {"comanda": ..., "confirmado": true}, which the turn
      # guard reads as no write at all — so a comanda that really opened would
      # have had its reply suppressed as a false confirmation.
      it 'says comanda_aberta so the reply is not thrown away' do
        allow(client).to receive(:open_comanda)
          .and_return('comanda' => { 'total_cents' => 15_000, 'intended_payment_method' => 'PIX' })

        body = JSON.parse(with_contact.call('abrir_comanda',
                                            { 'appointment_id' => 'a1', 'forma_pagamento' => 'PIX' }))

        expect(body['comanda_aberta']).to be(true)
        expect(body['valor_centavos']).to eq(15_000)
        expect(body['forma_pagamento']).to eq('PIX')
      end

      it 'takes the phone from the contact, never from the model' do
        allow(client).to receive(:open_comanda).and_return('comanda' => {})

        with_contact.call('abrir_comanda',
                          { 'appointment_id' => 'a1', 'forma_pagamento' => 'PIX', 'client_phone' => '+5531000000000' })

        expect(client).to have_received(:open_comanda)
          .with('a1', hash_including(client_phone: '+5531999999999'))
      end

      # Money moved, or may have. The turn must not replay either way.
      it 'marks the turn as written even when the salon refuses' do
        allow(client).to receive(:open_comanda).and_raise(Ai::Belezaki::AgentClient::Error, 'timeout')
        executor = with_contact

        executor.call('abrir_comanda', { 'appointment_id' => 'a1', 'forma_pagamento' => 'PIX' })

        expect(executor.performed_write?).to be(true)
      end

      # Before these codes existed the agent could only improvise an excuse.
      it 'tells the agent to offer somebody else when the professional is refused' do
        allow(client).to receive(:services)
          .and_raise(Ai::Belezaki::AgentClient::Error.new('x', code: 'professional_does_not_offer'))

        body = JSON.parse(tools.call('listar_servicos', {}))

        expect(body['message']).to include('Consulte quem faz')
      end
    end

    describe 'writing the failure down on the connection' do
      let(:account) { create(:account) }
      let(:assistant) { create(:ai_assistant, account: account) }
      let(:connection) do
        Ai::Belezaki::Connection.create!(ai_assistant: assistant, account: account, external_id: 'ext-1')
      end

      def failing(code)
        allow(client).to receive(:services)
          .and_raise(Ai::Belezaki::AgentClient::Error.new('salão sumiu', code: code))
        described_class.new(client, scope: 'conv-1', connection: connection).call('listar_servicos', {})
        connection.reload
      end

      # The screen would otherwise keep saying "connected" while the agent has
      # quietly lost the ability to book, and nobody finds out until a customer
      # does.
      it 'revokes when the salon or the link is gone' do
        expect(failing('http_404')).not_to be_active
      end

      # Our shared key and our configuration: every connection on the platform is
      # affected, and sending this one operator to reconnect fixes nothing while
      # making it look like their fault.
      it 'records a configuration failure without revoking the binding' do
        result = failing('http_503')

        expect(result).to be_active
        expect(result.last_error).to eq('salão sumiu')
      end

      # A blip was already retried. Stamping it would cry wolf on the screen for
      # something that fixed itself a second later.
      # Their billing, not this operator's onboarding: reconnecting would fix
      # nothing, so the binding stays and the reason goes on the card.
      it 'records a lapsed subscription without unbinding the agenda' do
        result = failing('entitlement_inactive')

        expect(result).to be_active
        expect(result.last_error).to be_present
      end

      it 'says nothing about a transient failure' do
        expect(failing('http_429').last_error).to be_nil
      end

      # A screen that failed to update is not a reason to lose the reply the
      # customer is waiting for.
      it 'still answers the model when the row cannot be written' do
        allow(connection).to receive(:revoke!).and_raise(ActiveRecord::RecordInvalid)
        allow(client).to receive(:services)
          .and_raise(Ai::Belezaki::AgentClient::Error.new('x', code: 'http_404'))

        result = described_class.new(client, scope: 'conv-1', connection: connection).call('listar_servicos', {})

        expect(result).to include('http_404')
      end
    end

    describe 'the booking answer' do
      # The turn guard reads a booking off `"agendado": true`. belezaki answers
      # `{"appointment": {"status": "confirmed"}}`, which matches nothing — so
      # without normalising it every SUCCESSFUL booking would have its reply
      # thrown away as a confirmation of something that never happened.
      it 'says agendado when the salon confirmed' do
        allow(client).to receive(:create_appointment).and_return(
          'appointment' => { 'id' => 'a1', 'status' => 'confirmed', 'start' => '2026-06-20T16:00:00-03:00' }
        )

        body = JSON.parse(tools.call('agendar', booking_input))

        expect(body['agendado']).to be(true)
        expect(body['inicio']).to eq('2026-06-20T16:00:00-03:00')
      end

      # A replay of a key whose appointment was cancelled also answers 201, with
      # `"status": "canceled"`. HTTP success is not the same as an appointment.
      it 'does not claim a booking when the status is not confirmed' do
        allow(client).to receive(:create_appointment).and_return(
          'appointment' => { 'id' => 'a1', 'status' => 'canceled' }
        )

        body = JSON.parse(tools.call('agendar', booking_input))

        expect(body['agendado']).to be(false)
        expect(body['motivo']).to include('canceled')
      end

      it 'does not claim a booking when the salon answered nothing usable' do
        allow(client).to receive(:create_appointment).and_return({})

        expect(JSON.parse(tools.call('agendar', booking_input))['agendado']).to be(false)
      end
    end

    describe 'validation before the call' do
      # 2026-02-30 does not fail on their side: it answers 200 with the real
      # slots of March 2nd under an envelope that says February 30th, so the
      # agent would offer a day that does not exist.
      it 'refuses a date that is not a real day, without calling the salon' do
        expect(client).not_to receive(:availability)

        body = JSON.parse(tools.call('consultar_horarios', { 'service_id' => 's1', 'date' => '2026-02-30' }))

        expect(body['error']).to eq('invalid_input')
      end

      # A missing date reaches Prisma as NaN and comes back as a 500, which the
      # agent would then treat as transient and retry.
      it 'refuses a missing date' do
        expect(client).not_to receive(:availability)

        expect(tools.call('consultar_horarios', { 'service_id' => 's1' })).to include('invalid_input')
      end

      it 'refuses a start it cannot parse, so nothing is written' do
        expect(client).not_to receive(:create_appointment)
        executor = tools

        executor.call('agendar', booking_input('start' => 'sexta que vem'))

        expect(executor.performed_write?).to be(false)
      end

      it 'lets a real date through' do
        allow(client).to receive(:availability).and_return({ 'slots' => [] })

        tools.call('consultar_horarios', { 'service_id' => 's1', 'date' => '2026-06-20' })

        expect(client).to have_received(:availability)
      end
    end

    # Omitted, the salon opens a second transaction just to pick somebody and can
    # land on a professional its own book then rejects with a 400 — after the
    # customer was already offered the time.
    it 'requires the professional the slot came from' do
      schema = described_class.definitions(include_booking: true).find { |t| t[:name] == 'agendar' }

      expect(schema[:input_schema][:required]).to include('professional_id')
    end

    # The salon holds the book, so the confirmation is the only moment the
    # appointment is ours to write down. It used to be handed to the model and
    # dropped, which left every commercial number blind to the agenda that books
    # the most. Ai::Belezaki::BookingRecorder covers the writing itself; what
    # matters here is that the tool actually calls it.
    describe 'writing the booking down on our side' do
      let(:account) { create(:account) }
      let(:assistant) { create(:ai_assistant, account: account) }
      let(:conversation) { create(:conversation, account: account) }
      let(:connection) do
        Ai::Belezaki::Connection.create!(
          ai_assistant: assistant, account: account, external_id: 'salon-1', status: 'active'
        )
      end

      def bound_tools
        described_class.new(client, scope: 'conv-1', connection: connection, conversation: conversation)
      end

      def confirmed(overrides = {})
        { 'appointment' => { 'id' => 'apt-1', 'status' => 'confirmed', 'price_cents' => 9_000 }.merge(overrides) }
      end

      it 'records a confirmed booking as attributed revenue' do
        allow(client).to receive(:create_appointment).and_return(confirmed)

        bound_tools.call('agendar', booking_input)

        expect(Ai::RevenueEvent.where(account_id: account.id).count).to eq(1)
      end

      # A booking the salon refused is not a sale, and the agent already tells
      # the customer so.
      it 'records nothing when the salon did not confirm' do
        allow(client).to receive(:create_appointment).and_return(confirmed('status' => 'canceled'))

        bound_tools.call('agendar', booking_input)

        expect(Ai::RevenueEvent.count).to be_zero
      end
    end
  end
end
