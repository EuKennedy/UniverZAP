require 'rails_helper'

RSpec.describe Ai::AutopilotReplyService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account, tone: 'sales') }
  let(:conversation) { create(:conversation, account: account) }
  let(:claude) { instance_double(Ai::ClaudeService) }
  let(:summarizer) { instance_double(Ai::SummarizeService, perform: { content: 'memo' }) }
  let(:asked_before) { 'Qual o tipo do seu fio? Tem química? O que você mais precisa?' }

  before do
    allow(Ai::SummarizeService).to receive(:new).and_return(summarizer)
    allow(Ai::ClaudeService).to receive(:new).and_return(claude)
    create(:message, conversation: conversation, account: account, message_type: 'incoming', content: 'quero comprar')
    create(:message, conversation: conversation, account: account, message_type: 'outgoing', content: asked_before)
  end

  describe '#perform loop-breaker' do
    it 'suppresses the reply when it repeats a recent assistant turn' do
      allow(claude).to receive(:chat).and_return({ content: asked_before, model: 'claude' })

      expect { described_class.new(conversation: conversation, assistant: assistant).perform }
        .to raise_error(described_class::LoopSuppressed)
    end

    it 'regenerates once before giving up (calls Claude twice)' do
      allow(claude).to receive(:chat).and_return({ content: asked_before, model: 'claude' })

      begin
        described_class.new(conversation: conversation, assistant: assistant).perform
      rescue described_class::LoopSuppressed
        nil
      end

      expect(claude).to have_received(:chat).twice
    end

    it 'returns the reply when it does not repeat a recent turn' do
      allow(claude).to receive(:chat).and_return({ content: 'Fechado! Te mando o link agora.', model: 'claude' })

      result = described_class.new(conversation: conversation, assistant: assistant).perform

      expect(result[:content]).to include('link')
    end
  end

  describe 'context de-poison (build_recent_messages)' do
    it 'collapses repeated assistant turns and opens with a user turn' do
      conv = create(:conversation, account: account)
      create(:message, conversation: conv, account: account, message_type: 'incoming', content: 'oi')
      3.times do
        create(:message, conversation: conv, account: account, message_type: 'outgoing',
                         content: 'Qual o tipo do seu fio? Tem química? O que você mais precisa?')
      end
      create(:message, conversation: conv, account: account, message_type: 'incoming', content: 'quero comprar')

      msgs = described_class.new(conversation: conv, assistant: assistant).send(:build_recent_messages)

      expect(msgs.count { |m| m[:role] == 'assistant' }).to eq(1)
      expect(msgs.first[:role]).to eq('user')
      expect(msgs.each_cons(2).none? { |a, b| a[:role] == b[:role] }).to be(true)
    end
  end

  describe 'contact personalisation + knowledge relevance (Sprint 5)' do
    it 'injects the contact name / phone / custom fields into the system prompt block' do
      conversation.contact.update!(
        name: 'Marina', phone_number: '+5531999990000',
        custom_attributes: { 'tipo_de_fio' => 'cacheado' }
      )

      block = described_class.new(conversation: conversation, assistant: assistant).send(:contact_block)

      expect(block).to include('Marina', '+5531999990000', 'tipo_de_fio', 'cacheado')
    end

    it 'omits the contact block when the contact has no usable data' do
      conversation.contact.update!(name: '', phone_number: nil, email: nil, custom_attributes: {})

      block = described_class.new(conversation: conversation, assistant: assistant).send(:contact_block)

      expect(block).to be_nil
    end

    it 'builds the knowledge query from the recent incoming messages' do
      query = described_class.new(conversation: conversation, assistant: assistant).send(:knowledge_query)

      expect(query).to include('quero comprar')
    end
  end

  describe 'replay safety after an external booking (Sprint 8)' do
    let(:service) { described_class.new(conversation: conversation, assistant: assistant) }

    it 'downgrades to a permanent error once a booking landed, so the turn is never replayed' do
      allow(service).to receive(:generate_response) do
        service.instance_variable_set(:@performed_external_write, true)
        raise Ai::ClaudeService::TransientError, 'Claude API 503'
      end

      expect { service.perform }.to raise_error(an_instance_of(Ai::ClaudeService::Error))
    end

    it 'keeps the failure retryable when no booking was attempted' do
      allow(service).to receive(:generate_response).and_raise(Ai::ClaudeService::TransientError, 'Claude API 503')

      expect { service.perform }.to raise_error(Ai::ClaudeService::TransientError)
    end

    it 'records the external write for the whole turn, not just inside the tool loop' do
      executor = instance_double(Ai::Belezaki::SchedulingTools, performed_write?: true)
      loop_service = instance_double(Ai::Agent::ToolLoopService, perform: { content: 'ok' })
      allow(Ai::Agent::ToolLoopService).to receive(:new).and_return(loop_service)

      service.send(:run_tool_loop, [], executor)

      expect(service.instance_variable_get(:@performed_external_write)).to be(true)
    end
  end

  describe 'summary persistence (Sprint 8)' do
    it 'does not clobber the reply dedup stamp written concurrently by another job' do
      # The service captures its snapshot here, BEFORE the concurrent write.
      service = described_class.new(conversation: conversation, assistant: assistant)
      # Another job stamps the dedup key out-of-band (same row, different object),
      # exactly like AutopilotReplyJob#mark_replied! does under the row lock.
      Conversation.find(conversation.id).update!(additional_attributes: { 'autopilot_last_replied_message_id' => 4242 })

      service.send(:persist_summary, 'memo novo')

      attrs = conversation.reload.additional_attributes
      expect(attrs['autopilot_last_replied_message_id']).to eq(4242)
      expect(attrs.dig('autopilot_summary', 'text')).to eq('memo novo')
    end

    # Regression: an in-memory mirror left the record dirty and the job's
    # conversation.lock! then raised "Locking a record with unpersisted changes".
    it 'leaves the conversation clean so the caller can still lock it' do
      service = described_class.new(conversation: conversation, assistant: assistant)

      service.send(:persist_summary, 'memo novo')

      expect(conversation.has_changes_to_save?).to be(false)
    end
  end
end
