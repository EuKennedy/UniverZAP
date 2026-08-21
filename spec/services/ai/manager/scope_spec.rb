# frozen_string_literal: true

require 'rails_helper'

# A porta única de leitura do Gerente. O que este arquivo prova é `bookings`, o
# leitor que junta as DUAS agendas, porque foi a falta dele que deixou a
# verificação crítica muda em produção para todo cliente de salão.
RSpec.describe Ai::Manager::Scope do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:booked_at) { 2.days.ago }
  let(:scope) do
    described_class.for_account(account, Ai::Reports::Period.from_days(30)).for_assistant(assistant)
  end

  # Existir já define o fuso do negócio para o relógio da conta, que é o fuso em
  # que o horário do belezaki tem que ser lido.
  let(:professional) do
    Ai::Calendar::Connection.create!(
      ai_assistant: assistant, account: account, google_email: 'salao@gmail.com', encrypted_refresh_token: 'rt'
    ).professionals.create!(
      ai_assistant_id: assistant.id, account_id: account.id,
      name: 'Ana', calendar_id: 'primary', timezone: 'America/Sao_Paulo'
    )
  end

  before { professional }

  def google_booking(hour, status: 'booked')
    starts_at = zone.local(2026, 9, 3, hour, 0)
    Ai::Calendar::Appointment.create!(
      ai_calendar_professional_id: professional.id, ai_assistant_id: assistant.id,
      account_id: account.id, contact_id: contact.id, conversation_id: conversation.id,
      google_event_id: "evt-#{SecureRandom.hex(4)}", starts_at: starts_at, ends_at: starts_at + 1.hour,
      status: status, created_at: booked_at, updated_at: booked_at
    )
  end

  # Exatamente o que Ai::Belezaki::BookingRecorder#booked escreve: source
  # `agendamento`, recorded_by `agent`, o id do salão no external_ref com o
  # prefixo dele, e o horário como string ISO dentro do metadata.
  def belezaki_booking(starts_at, agent: nil, on_conversation: nil)
    target = agent || assistant
    create(
      :ai_revenue_event,
      account: target.account, ai_assistant: target,
      conversation_id: (on_conversation || conversation).id,
      source: Ai::Belezaki::BookingRecorder::SOURCE,
      recorded_by: Ai::Belezaki::BookingRecorder::RECORDER,
      external_ref: "#{Ai::Belezaki::BookingRecorder::REF_PREFIX}#{SecureRandom.uuid}",
      occurred_at: booked_at, amount_brl: 120.0,
      metadata: { 'state' => 'booked', 'starts_at' => starts_at }
    )
  end

  describe '#bookings' do
    it 'traz o agendamento do Google' do
      google_booking(13)

      expect(scope.bookings.map(&:source)).to eq(['google'])
      expect(scope.bookings.first.starts_at.in_time_zone(zone).hour).to eq(13)
    end

    # O caso que não existia. Todo agendamento de salão que usa belezaki mora
    # aqui, e a verificação crítica lia só a tabela do Google.
    it 'traz o agendamento do belezaki, que não tem linha na agenda do Google' do
      belezaki_booking('2026-09-03T13:00:00-03:00')

      booking = scope.bookings.first

      expect(booking.source).to eq('belezaki')
      expect(booking.conversation_id).to eq(conversation.id)
      expect(booking.starts_at.in_time_zone(zone).hour).to eq(13)
    end

    it 'junta as duas agendas numa lista só' do
      google_booking(13)
      belezaki_booking('2026-09-03T15:00:00-03:00')

      expect(scope.bookings.map(&:source)).to contain_exactly('google', 'belezaki')
    end

    # Um evento de receita que não é agendamento é venda avulsa. Contá-lo como
    # agendamento acusaria o agente por um horário que ninguém marcou.
    it 'não traz o evento de receita que não é agendamento' do
      create(:ai_revenue_event, account: account, ai_assistant: assistant, conversation_id: conversation.id,
                                source: 'pedido', recorded_by: 'operator', occurred_at: booked_at,
                                external_ref: 'woo:order:991', metadata: { 'starts_at' => '2026-09-03T13:00:00-03:00' })

      expect(scope.bookings).to be_empty
    end

    # Uma linha com horário nulo estouraria dentro da verificação, o `safely` do
    # AnalysisService engoliria a rodada daquele agente, e a auditoria voltaria a
    # falhar calada. Descartar é a única saída honesta.
    it 'descarta a linha sem starts_at em vez de devolver horário nulo' do
      belezaki_booking(nil)

      expect(scope.bookings).to be_empty
    end

    it 'descarta a linha cujo starts_at não é data e hora' do
      belezaki_booking('quinta às 14h')

      expect(scope.bookings).to be_empty
    end

    it 'descarta a linha cujo starts_at é uma data que não existe' do
      belezaki_booking('2026-02-30T13:00:00-03:00')

      expect(scope.bookings).to be_empty
    end

    # Sem deslocamento, a string é hora local do salão. Lida como UTC, o
    # agendamento anda três horas, que numa verificação de horário é a diferença
    # entre acusar e absolver.
    it 'lê o horário sem deslocamento no fuso do negócio, e não em UTC' do
      belezaki_booking('2026-09-03T13:00:00')

      expect(scope.bookings.first.starts_at.in_time_zone(zone).hour).to eq(13)
    end

    it 'não traz o agendamento do Google que foi cancelado' do
      google_booking(13, status: 'cancelled')

      expect(scope.bookings).to be_empty
    end

    it 'não traz agendamento sem conversa, que não tem confirmação para comparar' do
      belezaki_booking('2026-09-03T13:00:00-03:00').update!(conversation_id: nil)

      expect(scope.bookings).to be_empty
    end

    it 'não traz o agendamento que ficou fora da janela' do
      belezaki_booking('2026-09-03T13:00:00-03:00').update!(occurred_at: 45.days.ago)

      expect(scope.bookings).to be_empty
    end

    # A regra mais importante desta base. O escopo estreita por conta SEMPRE,
    # mesmo quando o agente já implicaria a conta.
    it 'nunca traz o agendamento de outra conta' do
      stranger = create(:ai_assistant, account: create(:account))
      other = create(:conversation, account: stranger.account)
      belezaki_booking('2026-09-03T13:00:00-03:00', agent: stranger, on_conversation: other)

      expect(scope.bookings).to be_empty
      expect(described_class.for_account(account, Ai::Reports::Period.from_days(30)).bookings).to be_empty
    end

    it 'nunca traz o agendamento de outro agente da mesma conta' do
      rival = create(:ai_assistant, account: account)
      belezaki_booking('2026-09-03T13:00:00-03:00', agent: rival)

      expect(scope.bookings).to be_empty
    end

    it 'devolve o mais recente primeiro, que é o caso que o operador consegue conferir' do
      belezaki_booking('2026-09-03T13:00:00-03:00').update!(occurred_at: 10.days.ago)
      recent = belezaki_booking('2026-09-04T13:00:00-03:00')

      expect(scope.bookings.first.id).to eq(recent.id)
    end
  end

  # A régua de amostra tem que medir o mesmo conjunto que a auditoria varre.
  describe '#conversations_by_assistant e #conversations_count_for' do
    let(:account_scope) { described_class.for_account(account, Ai::Reports::Period.from_days(30)) }
    let(:rival) { create(:ai_assistant, account: account) }

    def reply(agent, conversation_id)
      create(:ai_invocation, account: account, ai_assistant: agent, conversation_id: conversation_id,
                             message_id: conversation_id, ai_response: 'Prontinho!', created_at: 2.days.ago)
    end

    before do
      reply(assistant, 501)
      reply(assistant, 502)
      reply(rival, 503)
    end

    it 'conta as conversas de cada agente separadamente' do
      expect(account_scope.conversations_by_assistant).to eq(assistant.id => 2, rival.id => 1)
    end

    it 'conta só as conversas dos agentes pedidos' do
      expect(account_scope.conversations_count_for([assistant.id])).to eq(2)
    end

    it 'não conta a mesma conversa duas vezes quando dois agentes atenderam nela' do
      reply(rival, 501)

      expect(account_scope.conversations_count_for([assistant.id, rival.id])).to eq(3)
    end

    it 'devolve zero sem agente nenhum, em vez de contar a conta inteira' do
      expect(account_scope.conversations_count_for([])).to eq(0)
    end
  end

  describe '#display_ids_for' do
    it 'traduz a chave primária no número que a URL do Chatwoot usa' do
      expect(scope.display_ids_for([conversation.id])).to eq(conversation.id => conversation.display_id)
    end

    it 'não traduz a conversa de outra conta' do
      stranger = create(:conversation, account: create(:account))

      expect(scope.display_ids_for([stranger.id])).to be_empty
    end
  end
end
