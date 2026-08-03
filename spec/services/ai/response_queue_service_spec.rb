# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ResponseQueueService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  def reply(**attrs)
    create(:ai_invocation, account: account, ai_assistant: assistant, phase: 'autopilot',
                           conversation_id: conversation.id, ai_response: 'texto', **attrs)
  end

  def flags_of(result)
    result[:items].pluck(:auto_flag)
  end

  describe 'what belongs in the queue' do
    # A suppressed reply never reached a customer, and it is exactly the one
    # worth reading: it is the agent trying to invent a price.
    it 'includes a reply the guardrails refused to send' do
      reply(delivery_status: 'failed', handoff: true, auto_flag: 'preco_inventado',
            auto_flags: ['preco_inventado'], message_id: nil)

      expect(described_class.new(assistant: assistant).perform[:total]).to eq(1)
    end

    it 'excludes calls that never produced text' do
      reply(ai_response: nil)

      expect(described_class.new(assistant: assistant).perform[:total]).to eq(0)
    end

    it 'excludes playground turns' do
      reply(sandbox: true, auto_flag: 'sem_fonte', auto_flags: ['sem_fonte'])

      expect(described_class.new(assistant: assistant).perform[:total]).to eq(0)
    end

    it 'never returns another account agent' do
      other = create(:ai_assistant, account: create(:account))
      reply

      expect(described_class.new(assistant: other).perform[:total]).to eq(0)
    end
  end

  describe 'ordering' do
    # The queue is read top-down: a fabricated price must never sit below
    # yesterday's low-confidence note.
    it 'puts the worst flag first, regardless of recency' do
      reply(auto_flag: 'baixa_confianca', auto_flags: ['baixa_confianca'], created_at: 1.minute.ago)
      reply(auto_flag: 'preco_inventado', auto_flags: ['preco_inventado'], created_at: 2.days.ago)
      reply(auto_flag: nil, created_at: 10.seconds.ago)

      expect(flags_of(described_class.new(assistant: assistant).perform))
        .to eq(%w[preco_inventado baixa_confianca] + [nil])
    end

    it 'falls back to recency inside the same flag' do
      old = reply(auto_flag: 'sem_fonte', auto_flags: ['sem_fonte'], created_at: 3.days.ago)
      recent = reply(auto_flag: 'sem_fonte', auto_flags: ['sem_fonte'], created_at: 1.hour.ago)

      ids = described_class.new(assistant: assistant).perform[:items].pluck(:id)
      expect(ids).to eq([recent.id, old.id])
    end
  end

  describe 'filters' do
    before do
      reply(auto_flag: 'sem_fonte', auto_flags: ['sem_fonte'])
      reply(auto_flag: nil)
    end

    it 'shows everything by default' do
      expect(described_class.new(assistant: assistant).perform[:total]).to eq(2)
    end

    it 'narrows to flagged' do
      expect(described_class.new(assistant: assistant, filter: 'flagged').perform[:total]).to eq(1)
    end

    it 'narrows to a single flag' do
      expect(described_class.new(assistant: assistant, flag: 'sem_fonte').perform[:total]).to eq(1)
    end

    it 'separates reviewed from unreviewed' do
      reviewed = Ai::Invocation.last
      create(:ai_response_feedback, account: account, ai_assistant: assistant,
                                    ai_invocation: reviewed, reviewer: admin, rating: 'up')

      expect(described_class.new(assistant: assistant, filter: 'reviewed').perform[:total]).to eq(1)
      expect(described_class.new(assistant: assistant, filter: 'unreviewed').perform[:total]).to eq(1)
    end

    it 'ignores an unknown filter instead of returning nothing' do
      expect(described_class.new(assistant: assistant, filter: 'sql; drop').perform[:total]).to eq(2)
    end
  end

  describe 'the payload a reviewer needs' do
    it 'carries the question, the answer, the sources and the verdict' do
      row = reply(user_message: 'quanto custa?', ai_response: 'R$ 10,00',
                  chunks_used: [{ 'title' => 'Tabela', 'score' => 0.4, 'chars' => 120 }])
      create(:ai_response_feedback, account: account, ai_assistant: assistant,
                                    ai_invocation: row, reviewer: admin, rating: 'up')

      item = described_class.new(assistant: assistant).perform[:items].first

      expect(item[:user_message]).to eq('quanto custa?')
      expect(item[:sources]).to eq(['Tabela'])
      expect(item[:feedback][:rating]).to eq('up')
    end
  end
end
