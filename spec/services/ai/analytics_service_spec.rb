require 'rails_helper'

RSpec.describe Ai::AnalyticsService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  def invocation(attrs = {})
    Ai::Invocation.create!(
      { ai_assistant: assistant, account: account, conversation_id: conversation.id,
        phase: 'autopilot', model: 'claude-sonnet-4-5', input_tokens: 100, output_tokens: 50,
        cost_usd: 0.01, duration_ms: 1000, status: 'success' }.merge(attrs)
    )
  end

  it 'reports measured volume, cost and latency' do
    invocation(duration_ms: 1000, cost_usd: 0.01)
    invocation(duration_ms: 3000, cost_usd: 0.03)

    totals = described_class.new(assistant: assistant).perform[:totals]

    expect(totals[:calls]).to eq(2)
    expect(totals[:cost_usd]).to eq(0.04)
    expect(totals[:avg_latency_ms]).to eq(2000)
  end

  # A turn that uses the scheduling tools bills several Claude calls but sends
  # ONE message. Counting calls under a "Respostas" label would inflate the
  # headline number several times over.
  it 'counts replies by delivered message, not by Claude call' do
    message = create(:message, conversation: conversation, account: account, message_type: 'outgoing')
    3.times { invocation(message_id: message.id) }

    totals = described_class.new(assistant: assistant).perform[:totals]

    expect(totals[:replies]).to eq(1)
    expect(totals[:calls]).to eq(3)
  end

  it 'sums the whole turn cost onto the reply, not just the last call' do
    message = create(:message, conversation: conversation, account: account, message_type: 'outgoing')
    2.times { invocation(message_id: message.id, cost_usd: 0.02, duration_ms: 500) }
    Ai::ResponseHistoryRecorder.record!(assistant: assistant, conversation: conversation, message: message)

    reply = described_class.new(assistant: assistant).perform[:recent_replies].first

    expect(reply[:cost_usd]).to eq(0.04)
    expect(reply[:duration_ms]).to eq(1000)
  end

  # Without zero-fill the chart would squeeze a silent week into nothing and
  # misrepresent time.
  it 'returns one daily bucket per day in the window, including silent days' do
    invocation

    daily = described_class.new(assistant: assistant, days: 7).perform[:daily]

    expect(daily.length).to eq(7)
    expect(daily.count { |d| d[:calls].zero? }).to eq(6)
  end

  it 'separates failures from successes so reliability is visible' do
    invocation
    invocation(status: 'error', error_message: 'boom')

    totals = described_class.new(assistant: assistant).perform[:totals]

    expect(totals[:errors]).to eq(1)
    expect(totals[:success_rate]).to eq(50.0)
  end

  it 'reports the BRL actually debited, not a conversion of the USD figure' do
    inv = invocation
    Ai::CreditLedgerEntry.create!(account: account, kind: 'consumption', amount_cents_brl: -250, ai_invocation: inv)

    expect(described_class.new(assistant: assistant).perform[:totals][:cost_cents_brl]).to eq(250)
  end

  it 'shows the text the customer actually received next to its cost' do
    message = create(:message, conversation: conversation, account: account,
                               message_type: 'outgoing', content: 'Fica R$ 189,90.')
    invocation(message_id: message.id)
    Ai::ResponseHistoryRecorder.record!(assistant: assistant, conversation: conversation, message: message)

    replies = described_class.new(assistant: assistant).perform[:recent_replies]

    expect(replies.first[:content]).to eq('Fica R$ 189,90.')
    expect(replies.first[:duration_ms]).to eq(1000)
  end

  it 'never counts another agent invocations' do
    other = create(:ai_assistant, account: account)
    invocation(ai_assistant: other)

    expect(described_class.new(assistant: assistant).perform[:totals][:calls]).to eq(0)
  end

  it 'ignores invocations older than the requested window' do
    invocation(created_at: 40.days.ago)
    invocation

    expect(described_class.new(assistant: assistant, days: 30).perform[:totals][:calls]).to eq(1)
  end

  it 'returns an empty but well-formed payload for an agent that never ran' do
    result = described_class.new(assistant: assistant).perform

    expect(result[:totals][:calls]).to eq(0)
    expect(result[:totals][:success_rate]).to be_nil
    expect(result[:recent_replies]).to be_empty
  end

  describe 'supervision' do
    def delivered(attrs = {})
      message = create(:message, conversation: conversation, account: account, message_type: 'outgoing')
      invocation({ message_id: message.id }.merge(attrs))
    end

    it 'breaks the flags down so the recurring problem is visible' do
      delivered(auto_flag: 'preco_inventado', auto_flags: ['preco_inventado'])
      delivered(auto_flag: 'preco_inventado', auto_flags: ['preco_inventado'])
      delivered(auto_flag: 'sem_fonte', auto_flags: ['sem_fonte'])

      expect(described_class.new(assistant: assistant).perform[:flags])
        .to eq('preco_inventado' => 2, 'sem_fonte' => 1)
    end

    # Playground turns cost real money, so they belong in the spend figures, but
    # nobody needs to review an answer given to a fake customer.
    it 'keeps sandbox turns out of the review queue while keeping their cost' do
      delivered(auto_flag: 'sem_fonte', auto_flags: ['sem_fonte'], sandbox: true)

      result = described_class.new(assistant: assistant).perform

      expect(result[:flags]).to be_empty
      expect(result[:totals][:flagged]).to eq(0)
      expect(result[:totals][:calls]).to eq(1)
    end

    it 'counts replies that were generated and never delivered' do
      invocation(delivery_status: 'pending')

      expect(described_class.new(assistant: assistant).perform[:totals][:undelivered]).to eq(1)
    end

    it 'carries the flag, the confidence and the question into the recent list' do
      message = create(:message, conversation: conversation, account: account, message_type: 'outgoing')
      invocation(message_id: message.id, auto_flag: 'baixa_confianca', confidence: 0.42, user_message: 'quanto custa?')
      Ai::ResponseHistoryRecorder.record!(assistant: assistant, conversation: conversation, message: message)

      reply = described_class.new(assistant: assistant).perform[:recent_replies].first

      expect(reply[:auto_flag]).to eq('baixa_confianca')
      expect(reply[:confidence]).to eq(0.42)
      expect(reply[:user_message]).to eq('quanto custa?')
    end
  end
end
