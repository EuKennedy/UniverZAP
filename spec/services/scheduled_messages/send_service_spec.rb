# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScheduledMessages::SendService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Bia Lima', phone_number: '+5531900000001') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:scheduled) do
    travel_to(zone.parse('2026-10-20 08:00')) do
      create(:scheduled_message, conversation: conversation, created_by: agent, send_at: zone.parse('2026-10-20 10:00'))
    end
  end

  def deliver(at: zone.parse('2026-10-20 10:00'))
    scheduled.update_columns(status: ScheduledMessage.statuses[:sending]) # rubocop:disable Rails/SkipsModelValidations
    travel_to(at) { described_class.new(scheduled.reload).perform }
    scheduled.reload
  end

  it 'vira mensagem da conversa, com as variáveis preenchidas, em nome de quem agendou' do
    expect(deliver).to be_status_sent

    message = Message.find(scheduled.message_id)
    expect(message).to have_attributes(content: 'Oi Bia, tudo bem?', message_type: 'outgoing', sender: agent)
  end

  it 'não sai para quem pediu opt-out' do
    contact.update!(custom_attributes: { 'opt_out_disparos' => true })

    expect(deliver).to have_attributes(status: 'cancelled', cancel_reason: 'opted_out')
  end

  it 'passo de sequência fora do horário comercial volta para a fila na próxima abertura' do
    scheduled.update!(respect_window: true)

    result = deliver(at: zone.parse('2026-10-20 21:00'))
    expect(result).to be_status_scheduled
    expect(result.send_at).to be_between(zone.parse('2026-10-21 09:00'), zone.parse('2026-10-21 09:15'))
  end

  it 'um erro vira falha visível em vez de explodir' do
    allow(Messages::MessageBuilder).to receive(:new).and_raise(StandardError, 'sessão caiu')

    expect(deliver).to have_attributes(status: 'failed', error: 'sessão caiu')
  end
end
