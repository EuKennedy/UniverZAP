require 'rails_helper'

RSpec.describe WahaDelayedDelivery do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, additional_attributes: { source: 'waha' }) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:stamped_text) { "Oi\n`🗓️ sex., 30 de out. • 19:37 UTC`" }
  let(:sent_at) { Time.utc(2026, 10, 30, 19, 37) }

  def deliver(content, type: :incoming, target: conversation)
    create(:message, account: account, inbox: target.inbox, conversation: target, message_type: type, content: content)
  end

  around { |example| travel_to(Time.utc(2026, 11, 5, 15)) { example.run } }

  it 'creates the message at the real time and drops the stamp' do
    message = deliver(stamped_text)

    expect(message.created_at).to eq(sent_at)
    expect(message.content).to eq('Oi')
    expect(message).to be_delayed_delivery
  end

  it 'keeps the conversation at the date of the message' do
    deliver(stamped_text)

    expect(conversation.reload.last_activity_at).to eq(sent_at)
    expect(conversation.created_at).to eq(sent_at)
  end

  it 'reads the stamp of a history import' do
    expect(deliver("Oi\n`📥🗓️ Hoje, 05 de nov. • 11:20 UTC`").created_at).to eq(Time.utc(2026, 11, 5, 11, 20))
  end

  it 'does not move a conversation that already has a newer message' do
    deliver('Mensagem nova')
    last_activity = conversation.reload.last_activity_at
    deliver(stamped_text)

    expect(conversation.reload.last_activity_at).to eq(last_activity)
  end

  it 'does not change who has the last word when older than the newest message' do
    deliver('Respondido', type: :outgoing)
    conversation.update_columns(awaiting_reply: false) # rubocop:disable Rails/SkipsModelValidations
    deliver(stamped_text)

    expect(conversation.reload.awaiting_reply).to be(false)
  end

  it 'leaves a resolved conversation closed' do
    conversation.resolved!
    deliver(stamped_text)

    expect(conversation.reload).to be_resolved
  end

  it 'does not trigger bots, automations or greetings for history' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    deliver(stamped_text)

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Message::MESSAGE_CREATED, any_args)
  end

  it 'still treats a short delay as live' do
    conversation.resolved!
    deliver("Oi\n`🗓️ Hoje, 05 de nov. • 14:40 UTC`")

    expect(conversation.reload).to be_open
  end

  it 'ignores a stamp from the last two minutes' do
    message = deliver("Oi\n`🗓️ Hoje, 05 de nov. • 15:00 UTC`")

    expect(message.content).to include('UTC')
    expect(message).not_to be_delayed_delivery
  end

  it 'does not bring the conversation back with automatic activity' do
    deliver(stamped_text)
    deliver('Assigned by automation', type: :activity)

    expect(conversation.reload.last_activity_at).to eq(sent_at)
  end

  it 'leaves other inboxes alone' do
    other = create(:conversation, account: account, inbox: create(:channel_api, account: account).inbox)
    message = deliver(stamped_text, target: other)

    expect(message.created_at).to eq(Time.current)
    expect(message.content).to eq(stamped_text)
  end
end
