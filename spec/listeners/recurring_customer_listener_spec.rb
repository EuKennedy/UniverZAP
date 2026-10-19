require 'rails_helper'

describe RecurringCustomerListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:service) { instance_double(Conversations::RecurringCustomerService, perform: nil) }

  before do
    allow(Conversations::RecurringCustomerService).to receive(:new).and_return(service)
  end

  it 'runs the service when a conversation is created' do
    listener.conversation_created(Events::Base.new('conversation_created', Time.zone.now, conversation: conversation))

    expect(Conversations::RecurringCustomerService).to have_received(:new).with(conversation)
    expect(service).to have_received(:perform)
  end

  it 'is wired into the async dispatcher before the automation rules' do
    listeners = AsyncDispatcher.new.listeners.map(&:class)

    expect(listeners.index(described_class)).to be < listeners.index(AutomationRuleListener)
  end
end
