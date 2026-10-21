# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Broadcasts::RecipientGuard do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5531900000001') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:agent) { create(:user, account: account) }

  def reason
    described_class.new(contact: contact, quiet_hours: 12).skip_reason
  end

  it 'libera quem está quieto' do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, created_at: 2.days.ago)

    expect(reason).to be_nil
  end

  it 'segura quem pediu opt-out' do
    contact.update!(custom_attributes: { 'opt_out_disparos' => true })

    expect(reason).to eq('opted_out')
  end

  it 'segura quem escreveu nas últimas horas' do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming)

    expect(reason).to eq('recent_activity')
  end

  it 'segura quem um atendente acabou de responder' do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :outgoing, sender: agent)

    expect(reason).to eq('recent_activity')
  end

  it 'segura quem foi respondido pelo celular (nota da WAHA)' do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :outgoing,
                     private: true, content: '📱 Enviado do WhatsApp')

    expect(reason).to eq('recent_activity')
  end

  it 'não conta a própria mensagem automática (sem atendente)' do
    create(:message, :bot_message, conversation: conversation, account: account, inbox: conversation.inbox)

    expect(reason).to be_nil
  end

  it 'devolve os mesmos bloqueios em lote' do
    quiet = create(:contact, account: account, phone_number: '+5531900000002')
    opted = create(:contact, account: account, phone_number: '+5531900000003', custom_attributes: { 'opt_out_disparos' => 'true' })
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming)

    expect(described_class.blocked_ids(account, [contact.id, quiet.id, opted.id], quiet_hours: 12))
      .to eq(opted_out: [opted.id], recent_activity: [contact.id])
  end
end
