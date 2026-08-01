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

  describe 'knowledge grounding (anti-alucinação factual)' do
    let(:service) { described_class.new(conversation: conversation, assistant: assistant) }

    # ApplicationRecord caps every text column at 20_000 chars, so a fixture doc
    # has to stay under that while still dwarfing KNOWLEDGE_BUDGET_CHARS (6000).
    def training(title, content, category: 'catalog')
      Ai::Training.create!(
        account: account, ai_assistant: assistant, title: title, content: content,
        source_type: 'text', category: category, status: 'ready'
      )
    end

    # Regression: content was truncated to 240 chars per doc, so a price sitting
    # further into a catalog never reached the model and it invented one.
    it 'keeps a price that sits far beyond the old 240 char cut' do
      training('Tabela de preços', "#{'blá ' * 200}A Progressiva Premium custa R$ 189,90 à vista.")

      expect(service.send(:knowledge_snippets)).to include('R$ 189,90')
    end

    # The real shape of the bug: a catalog far bigger than the whole budget, with
    # the price deep inside it. Ranking has to be load-bearing here — truncation
    # or plain document order both lose the number.
    it 'surfaces a price buried in a document far larger than the budget' do
      conv = create(:conversation, account: account)
      create(:message, conversation: conv, account: account, message_type: 'incoming',
                       content: 'quanto custa a progressiva premium?')
      training('Catálogo', "#{'blá ' * 2000}Progressiva Premium: R$ 189,90 à vista.#{' blá' * 2000}")

      block = described_class.new(conversation: conv, assistant: assistant).send(:knowledge_snippets)

      expect(block).to include('R$ 189,90')
    end

    it 'keeps the line breaks of a row-oriented price table' do
      training('Tabela', "Progressiva Premium\nR$ 189,90\nBotox Capilar\nR$ 149,90")

      expect(service.send(:knowledge_snippets)).to include("Progressiva Premium\nR$ 189,90")
    end

    it 'caps the knowledge block so a huge catalog cannot blow up the prompt' do
      training('Catálogo gigante', 'palavra ' * 2000)

      block = service.send(:knowledge_snippets)

      expect(block.length).to be <= described_class::KNOWLEDGE_BUDGET_CHARS + 2000
    end

    # The unrelated doc is far bigger than the budget, so it would swallow the
    # whole block on document order alone. Only real ranking saves the price.
    it 'keeps the passage that answers the question when the budget forces a choice' do
      conv = create(:conversation, account: account)
      create(:message, conversation: conv, account: account, message_type: 'incoming',
                       content: 'qual o preço da progressiva premium?')
      training('Política de troca', 'Trocas em ate 7 dias corridos mediante nota fiscal. ' * 350)
      training('Preços', 'Progressiva Premium: R$ 189,90.')

      passages = described_class.new(conversation: conv, assistant: assistant).send(:relevant_passages)

      expect(passages.map { |p| p[:body] }.join(' ')).to include('R$ 189,90')
    end

    it 'never slices a price in half when splitting a document into passages' do
      body = "#{'x' * (described_class::KNOWLEDGE_CHUNK_CHARS - 5)} R$ 1.200,00 restante"

      chunks = service.send(:chunk_document, 'Preços', body)

      expect(chunks.any? { |c| c[:body].include?('R$ 1.200,00') }).to be(true)
    end

    it 'ships the hard anti-fabrication rule in every system prompt' do
      prompt = service.send(:build_system_prompt)

      expect(prompt).to include('REGRA DE VERACIDADE')
      expect(prompt).to include('NUNCA invente preço')
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
