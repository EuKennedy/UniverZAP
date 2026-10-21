# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MessageSequences::Planner do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let!(:sequence) do
    create(:message_sequence, account: account, enabled: true,
                              steps: [{ 'offset_minutes' => -1440, 'text' => 'Lembrete' },
                                      { 'offset_minutes' => 2880, 'text' => 'Como ficou?', 'cancel_if_reply' => false }])
  end

  def plan_for(appointment, now: zone.parse('2026-10-20 10:00'))
    conversation.update_columns(custom_attributes: { 'data_agendamento' => appointment&.iso8601 }.compact) # rubocop:disable Rails/SkipsModelValidations
    travel_to(now) { described_class.new(conversation.reload).perform }
  end

  # O pós cai num domingo e anda para segunda às 9h.
  it 'cria o lembrete 1 dia antes e o pós 2 dias depois' do
    plan_for(zone.parse('2026-10-23 15:00'))

    rows = conversation.scheduled_messages.pending.order(:send_at)
    expect(rows.map(&:send_at)).to eq([zone.parse('2026-10-22 15:00'), zone.parse('2026-10-26 09:00')])
    expect(rows.map(&:respect_window)).to all(be(true))
    expect(rows.last.cancel_if_reply).to be(false)
  end

  it 'lembrete que cairia na madrugada volta para a última hora aberta antes' do
    plan_for(zone.parse('2026-10-23 08:00'))

    expect(conversation.scheduled_messages.pending.order(:send_at).first.send_at).to eq(zone.parse('2026-10-21 18:30'))
  end

  it 'remarcar cancela o pendente e refaz; apagar o horário cancela tudo' do
    plan_for(zone.parse('2026-10-23 15:00'))
    plan_for(zone.parse('2026-10-24 15:00'))

    expect(conversation.scheduled_messages.status_cancelled.pluck(:cancel_reason).uniq).to eq(['rescheduled'])
    expect(conversation.scheduled_messages.pending.count).to eq(2)

    plan_for(nil)
    expect(conversation.scheduled_messages.pending.count).to eq(0)
  end

  it 'não cria passo que já passou nem usa sequência desligada' do
    sequence.update!(enabled: false)
    plan_for(zone.parse('2026-10-23 15:00'))
    expect(conversation.scheduled_messages.count).to eq(0)

    sequence.update!(enabled: true)
    plan_for(zone.parse('2026-10-20 18:00'))
    expect(conversation.scheduled_messages.pending.count).to eq(1)
  end
end
