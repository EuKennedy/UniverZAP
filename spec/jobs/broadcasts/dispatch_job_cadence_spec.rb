# frozen_string_literal: true

require 'rails_helper'

# Cadência anti-bloqueio do disparo: janela, tetos por conexão, guarda por
# destinatário, pausa por falhas e horário inteligente.
RSpec.describe Broadcasts::DispatchJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:contacts) { (1..3).map { |n| create(:contact, account: account, phone_number: "+553190000000#{n}") } }
  let(:throttle) { {} }
  let(:broadcast) do
    create(:broadcast, account: account, inbox: inbox, status: :running, audience: { 'contact_ids' => contacts.map(&:id) }, throttle: throttle)
  end
  let(:outcome) { :sent }

  before do
    allow(Broadcasts::RecipientSenderService).to receive(:new) do |recipient|
      sender = instance_double(Broadcasts::RecipientSenderService)
      allow(sender).to receive(:perform) do
        outcome == :sent ? recipient.update!(status: :sent, sent_at: Time.current) : recipient.update!(status: :failed, error: 'boom')
      end
      sender
    end
  end

  def run_at(time)
    travel_to(time) { described_class.perform_now(broadcast.id) }
  end

  it 'manda uma por vez e agenda a próxima com intervalo aleatório' do
    run_at(zone.parse('2026-10-20 10:00'))

    expect(broadcast.broadcast_recipients.status_sent.count).to eq(1)
    expect(enqueued_jobs.last[:job]).to eq(described_class)
  end

  it 'fora do horário comercial não envia e dorme até a abertura' do
    run_at(zone.parse('2026-10-24 20:00'))

    expect(broadcast.broadcast_recipients.status_sent.count).to eq(0)
    expect(Time.zone.at(enqueued_jobs.last[:at])).to be_between(zone.parse('2026-10-26 09:00'), zone.parse('2026-10-26 09:15'))
  end

  context 'with the connection hourly cap reached by another broadcast' do
    let(:throttle) { { 'hourly_cap' => 2 } }

    before do
      other = create(:broadcast, account: account, inbox: inbox)
      2.times { |n| create(:broadcast_recipient, broadcast: other, status: :sent, sent_at: zone.parse('2026-10-20 09:40') + n.minutes) }
    end

    it 'espera em vez de somar o volume' do
      run_at(zone.parse('2026-10-20 10:00'))

      expect(broadcast.broadcast_recipients.status_sent.count).to eq(0)
    end
  end

  it 'pula quem está em atendimento e segue para o próximo' do
    conversation = create(:conversation, account: account, contact: contacts.first, inbox: inbox)
    travel_to(zone.parse('2026-10-20 09:30')) do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
    end
    run_at(zone.parse('2026-10-20 10:00'))

    expect(broadcast.broadcast_recipients.find_by(contact: contacts.first)).to have_attributes(status: 'skipped', skip_reason: 'recent_activity')
    expect(broadcast.broadcast_recipients.status_sent.count).to eq(1)
  end

  context 'when failures repeat' do
    let(:outcome) { :failed }
    let(:throttle) { { 'max_failures' => 2 } }

    it 'pausa sozinho com o motivo' do
      run_at(zone.parse('2026-10-20 10:00'))
      run_at(zone.parse('2026-10-20 10:02'))

      expect(broadcast.reload).to have_attributes(status: 'paused', pause_reason: 'failures')
    end
  end

  context 'with smart timing' do
    let(:throttle) { { 'smart_timing' => true } }

    it 'segura a cliente até a hora em que ela costuma responder' do
      conversation = create(:conversation, account: account, contact: contacts.first, inbox: inbox)
      3.times do |n|
        create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming,
                         created_at: zone.parse("2026-10-1#{n + 1} 15:10"))
      end
      run_at(zone.parse('2026-10-20 10:00'))

      expect(broadcast.broadcast_recipients.find_by(contact: contacts.first)).to have_attributes(status: 'pending',
                                                                                                 send_after: zone.parse('2026-10-20 15:00'))
    end
  end

  context 'when scheduled for later' do
    let(:broadcast) do
      create(:broadcast, account: account, inbox: inbox, status: :scheduled, scheduled_at: zone.parse('2026-10-20 11:00'),
                         audience: { 'contact_ids' => contacts.map(&:id) })
    end

    it 'não começa antes da hora e começa na hora' do
      run_at(zone.parse('2026-10-20 10:00'))
      expect(broadcast.reload).to be_status_scheduled

      run_at(zone.parse('2026-10-20 11:00'))
      expect(broadcast.reload).to be_status_running
      expect(broadcast.broadcast_recipients.status_sent.count).to eq(1)
    end
  end

  describe 'uma corrente por lançamento' do
    it 'o job da corrente antiga não envia depois de relançar' do
      travel_to(zone.parse('2026-10-20 10:00')) do
        described_class.start(broadcast)
        old_token = enqueued_jobs.last[:args].last
        described_class.start(broadcast)

        described_class.perform_now(broadcast.id, old_token)
        expect(broadcast.broadcast_recipients.count).to eq(0)

        described_class.perform_now(broadcast.id, enqueued_jobs.last[:args].last)
        expect(broadcast.broadcast_recipients.status_sent.count).to eq(1)
      end
    end

    it 'job antigo sem token (enfileirado antes do deploy) continua valendo' do
      run_at(zone.parse('2026-10-20 10:00'))

      expect(broadcast.broadcast_recipients.status_sent.count).to eq(1)
    end
  end
end
