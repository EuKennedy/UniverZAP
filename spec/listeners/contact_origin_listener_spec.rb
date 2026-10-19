require 'rails_helper'

describe ContactOriginListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:service) { instance_double(Contacts::OriginService, perform: nil) }

  before do
    allow(Contacts::OriginService).to receive(:new).and_return(service)
  end

  it 'runs the service with the contact of an incoming message' do
    message = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi')

    listener.message_created(Events::Base.new('message_created', Time.zone.now, message: message))

    expect(Contacts::OriginService).to have_received(:new).with(conversation.contact)
    expect(service).to have_received(:perform)
  end

  it 'skips outgoing messages' do
    message = create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'oi')

    listener.message_created(Events::Base.new('message_created', Time.zone.now, message: message))

    expect(Contacts::OriginService).not_to have_received(:new)
  end

  it 'is wired into the async dispatcher right after the ad referral listener' do
    listeners = AsyncDispatcher.new.listeners.map(&:class)

    expect(listeners.index(described_class)).to eq(listeners.index(AdReferralListener) + 1)
  end
end
