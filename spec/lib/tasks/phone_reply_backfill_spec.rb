require 'rails_helper'
require 'rake'

RSpec.describe 'phone_reply:backfill', type: :task do
  let(:account) { create(:account) }
  let(:phone_reply) { "*📱 Enviado do WhatsApp*\nOi! Temos horário sábado às 10h." }

  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task['phone_reply:backfill'].reenable
  end

  def conversation_with(*messages)
    conversation = create(:conversation, account: account)
    messages.each { |type, options| create(:message, account: account, conversation: conversation, message_type: type, **options) }
    # Rows written before Message#phone_reply_note? existed: the note answered nothing.
    conversation.update!(awaiting_reply: true, waiting_since: conversation.created_at, first_reply_created_at: nil)
    conversation
  end

  it 'takes conversations whose last word is a reply typed in the phone out of Aguardando' do
    answered = conversation_with([:incoming, {}], [:outgoing, { private: true, content: phone_reply }])
    still_waiting = conversation_with([:incoming, {}], [:outgoing, { private: true, content: phone_reply }], [:incoming, {}])
    noted = conversation_with([:incoming, {}], [:outgoing, { private: true, content: 'ligar amanhã' }])

    expect { Rake::Task['phone_reply:backfill'].invoke(account.id) }.to output(/1 conversations/).to_stdout

    expect(answered.reload).to have_attributes(awaiting_reply: false, waiting_since: nil,
                                               first_reply_created_at: answered.messages.find_by(private: true).created_at)
    expect(still_waiting.reload).to have_attributes(awaiting_reply: true, first_reply_created_at: nil)
    expect(noted.reload).to have_attributes(awaiting_reply: true, first_reply_created_at: nil)
  end
end
