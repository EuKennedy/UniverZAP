# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::RoiService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  def spend(cents)
    invocation = create(:ai_invocation, account: account, ai_assistant: assistant,
                                        conversation_id: conversation.id)
    create(:ai_credit_ledger_entry, account: account, ai_invocation: invocation,
                                    kind: 'consumption', amount_cents_brl: -cents)
    invocation
  end

  def earn(amount, source: 'recuperado', at: Time.current)
    create(:ai_revenue_event, account: account, ai_assistant: assistant,
                              source: source, amount_brl: amount, occurred_at: at)
  end

  describe 'the number that justifies the top-up' do
    it 'divides attributed revenue by what was actually debited' do
      spend(1000)
      earn(250)

      expect(described_class.new(assistant: assistant).perform[:roi]).to eq(25.0)
    end

    # "0x return" reads as failure when the truth is "not measurable yet".
    it 'reports no ROI rather than zero when nothing was spent' do
      earn(250)

      expect(described_class.new(assistant: assistant).perform[:roi]).to be_nil
    end

    it 'uses the ledger, not a conversion of the USD figure' do
      spend(1234)

      expect(described_class.new(assistant: assistant).perform[:cost_brl]).to eq(12.34)
    end
  end

  describe 'per-unit costs' do
    it 'divides cost by distinct conversations, not by calls' do
      3.times { spend(300) }

      result = described_class.new(assistant: assistant).perform
      expect(result[:conversations]).to eq(1)
      expect(result[:cost_per_conversation_brl]).to eq(9.0)
    end

    it 'returns nil instead of dividing by zero bookings' do
      spend(500)

      expect(described_class.new(assistant: assistant).perform[:cost_per_booking_brl]).to be_nil
    end
  end

  describe 'hours saved' do
    it 'counts delivered replies and carries its own assumption' do
      message = create(:message, conversation: conversation, account: account, message_type: 'outgoing')
      create(:ai_invocation, account: account, ai_assistant: assistant,
                             conversation_id: conversation.id, message_id: message.id)

      result = described_class.new(assistant: assistant).perform
      expect(result[:replies]).to eq(1)
      expect(result[:hours_saved_assumption_seconds]).to eq(described_class::SECONDS_PER_HUMAN_REPLY)
    end
  end

  describe 'after-hours revenue' do
    # The strongest argument for the module: these would not exist, because
    # nobody was there to answer.
    it 'separates what came in outside business hours' do
      earn(100, at: Time.zone.parse('2026-07-15 22:30'))
      earn(400, at: Time.zone.parse('2026-07-15 14:00'))

      result = described_class.new(assistant: assistant, days: 365).perform
      expect(result[:revenue_brl]).to eq(500.0)
      expect(result[:after_hours_revenue_brl]).to eq(100.0)
    end
  end

  describe 'tenant scoping' do
    it 'never counts another agent revenue' do
      other = create(:ai_assistant, account: account)
      create(:ai_revenue_event, account: account, ai_assistant: other, amount_brl: 999)
      spend(100)

      expect(described_class.new(assistant: assistant).perform[:revenue_brl]).to eq(0.0)
    end
  end
end
