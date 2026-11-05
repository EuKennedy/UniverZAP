require 'rails_helper'

RSpec.describe Whatsapp::WahaHistoryReconcileJob do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_api, account: account, additional_attributes: { source: 'waha', session_name: 'sessao' })
  end
  let(:contact) do
    create(:contact, account: account, custom_attributes: { waha_whatsapp_chat_id: 'whatsapp.integration' })
  end
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: channel.inbox) }
  let!(:conversation) do
    create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:service) { instance_double(Whatsapp::WahaSessionService) }

  before { allow(Whatsapp::WahaSessionService).to receive(:new).with(session_name: 'sessao').and_return(service) }

  it 'asks a working session for what is missing' do
    allow(service).to receive(:session).and_return({ 'status' => 'WORKING' })

    described_class.perform_now

    message = conversation.messages.outgoing.last
    expect(message.content).to eq(described_class::COMMAND)
    expect(message.sender).to eq(admin)
  end

  it 'skips a session that is down' do
    allow(service).to receive(:session).and_return({ 'status' => 'FAILED' })

    expect { described_class.perform_now }.not_to(change { conversation.messages.outgoing.count })
  end

  it 'does not stop the other inboxes when one fails' do
    allow(service).to receive(:session).and_raise(StandardError, 'WAHA fora')

    expect { described_class.perform_now }.not_to raise_error
  end
end
