require 'rails_helper'

RSpec.describe Ai::ResponseHistoryRecorder do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  def delivered_turn(calls: 1, **attrs)
    message = create(:message, conversation: conversation, account: account, message_type: 'outgoing')
    calls.times do
      Ai::Invocation.create!(
        { ai_assistant: assistant, account: account, conversation_id: conversation.id,
          message_id: message.id, phase: 'autopilot', model: 'claude-sonnet-4-5',
          cost_usd: 0.01, cost_brl: 0.05, duration_ms: 400, status: 'success' }.merge(attrs)
      )
    end
    described_class.record!(assistant: assistant, conversation: conversation, message: message)
    message
  end

  # A tool-using turn bills several calls but is ONE reply: the projection must
  # collapse them into a single row carrying the summed cost of the whole turn.
  it 'projects one row per delivered reply with the whole turn summed' do
    delivered_turn(calls: 3)

    row = Ai::ResponseHistory.sole
    expect(row.calls).to eq(3)
    expect(row.duration_ms).to eq(1200)
    expect(row.cost_usd).to be_within(0.0001).of(0.03)
  end

  # The whole point of the module: the table never grows past the cap, so a
  # busy agent can serve forever without the history bloating the database.
  it 'keeps only the newest 100 replies per agent' do
    101.times { delivered_turn }

    expect(Ai::ResponseHistory.where(ai_assistant_id: assistant.id).count).to eq(100)
  end
end
