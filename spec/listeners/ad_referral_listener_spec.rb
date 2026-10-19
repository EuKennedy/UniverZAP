require 'rails_helper'

describe AdReferralListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:service) { instance_double(Conversations::AdReferralService, perform: nil) }

  before do
    allow(Conversations::AdReferralService).to receive(:new).and_return(service)
  end

  it 'runs the service for incoming messages' do
    message = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi')

    listener.message_created(Events::Base.new('message_created', Time.zone.now, message: message))

    expect(Conversations::AdReferralService).to have_received(:new).with(message)
    expect(service).to have_received(:perform)
  end

  it 'skips outgoing messages' do
    message = create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'oi')

    listener.message_created(Events::Base.new('message_created', Time.zone.now, message: message))

    expect(Conversations::AdReferralService).not_to have_received(:new)
  end

  it 'is wired into the async dispatcher' do
    expect(AsyncDispatcher.new.listeners.map(&:class)).to include(described_class)
  end
end
