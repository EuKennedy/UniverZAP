require 'rails_helper'

describe ScheduledMessageListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5531900000001') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  def customer_says(content, **attrs)
    message = create(:message, account: account, conversation: conversation, inbox: conversation.inbox, content: content,
                               message_type: :incoming, **attrs)
    listener.message_created(Events::Base.new('message_created', Time.zone.now, message: message))
  end

  describe 'a cliente escreveu antes do envio' do
    let!(:cancellable) { create(:scheduled_message, conversation: conversation) }
    let!(:kept) { create(:scheduled_message, conversation: conversation, cancel_if_reply: false) }

    it 'cancela só o que pede cancelamento' do
      customer_says('oi, tudo bem?')

      expect(cancellable.reload).to have_attributes(status: 'cancelled', cancel_reason: 'customer_replied')
      expect(kept.reload).to be_status_scheduled
    end

    it 'nota privada não conta como resposta' do
      customer_says('nota', private: true, message_type: :outgoing)

      expect(cancellable.reload).to be_status_scheduled
    end
  end

  it 'conta a resposta no relatório do disparo' do
    recipient = create(:broadcast_recipient, contact: contact, status: :sent, sent_at: 1.hour.ago)
    customer_says('quero agendar!')

    expect(recipient.reload.replied_at).to be_present
  end

  it 'aplica o opt-out quando a cliente pede' do
    customer_says('Não quero mais receber mensagens')

    expect(contact.reload.custom_attributes['opt_out_disparos']).to be(true)
  end

  it 'refaz as sequências quando o horário agendado muda' do
    planner = instance_double(MessageSequences::Planner, perform: [])
    allow(MessageSequences::Planner).to receive(:new).and_return(planner)
    change = { 'custom_attributes' => [{}, { 'data_agendamento' => '2026-10-25T17:00:00Z' }] }

    listener.conversation_updated(Events::Base.new('conversation_updated', Time.zone.now, conversation: conversation, changed_attributes: change))
    listener.conversation_updated(Events::Base.new('conversation_updated', Time.zone.now, conversation: conversation,
                                                                                          changed_attributes: { 'status' => %w[open resolved] }))

    expect(planner).to have_received(:perform).once
  end
end
