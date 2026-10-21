# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Broadcasts::BestTimeService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  def incoming_at(time)
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming, created_at: time)
  end

  it 'acha a hora em que a cliente mais escreve, no fuso do salão' do
    [1, 2, 3].each { |days| incoming_at(zone.parse("2026-10-1#{days} 14:20")) }
    incoming_at(zone.parse('2026-10-15 09:05'))

    travel_to(zone.parse('2026-10-20 10:00')) do
      expect(described_class.new(account).best_hours([contact.id])).to eq(contact.id => 14)
      expect(described_class.new(account).suggestion(contact)[:at]).to eq(zone.parse('2026-10-20 14:00'))
    end
  end

  it 'sem mensagens suficientes não inventa padrão' do
    incoming_at(1.day.ago)

    expect(described_class.new(account).best_hours([contact.id])).to eq({})
    expect(described_class.new(account).suggestion(contact)).to eq(hour: nil, at: nil)
  end
end
