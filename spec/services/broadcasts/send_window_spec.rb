# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Broadcasts::SendWindow do
  let(:account) { create(:account) }
  let(:window) { described_class.new(account: account, start_hour: 9, end_hour: 19, weekdays: [1, 2, 3, 4, 5, 6]) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  it 'abre no horário comercial de dia útil' do
    expect(window.open?(zone.parse('2026-10-20 10:00'))).to be(true)
  end

  it 'fecha de madrugada, depois das 19h e no domingo' do
    expect(window.open?(zone.parse('2026-10-20 07:59'))).to be(false)
    expect(window.open?(zone.parse('2026-10-20 19:00'))).to be(false)
    expect(window.open?(zone.parse('2026-10-25 11:00'))).to be(false)
  end

  it 'a próxima abertura depois do sábado à noite é segunda às 9h' do
    expect(window.next_open(zone.parse('2026-10-24 20:00'))).to eq(zone.parse('2026-10-26 09:00'))
  end

  it 'encaixa o horário preferido dentro da janela' do
    expect(window.next_at_hour(14, after: zone.parse('2026-10-20 10:00'))).to eq(zone.parse('2026-10-20 14:00'))
    expect(window.next_at_hour(22, after: zone.parse('2026-10-20 10:00'))).to eq(zone.parse('2026-10-20 18:00'))
    expect(window.next_at_hour(9, after: zone.parse('2026-10-20 10:00'))).to eq(zone.parse('2026-10-21 09:00'))
  end

  it 'usa o fuso de relatórios da conta' do
    account.update!(reporting_timezone: 'Asia/Tokyo')
    tokyo = ActiveSupport::TimeZone['Asia/Tokyo']

    expect(window.open?(tokyo.parse('2026-10-20 10:00'))).to be(true)
  end
end
