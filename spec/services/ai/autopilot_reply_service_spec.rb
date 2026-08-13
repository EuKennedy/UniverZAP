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

  # The tool discipline shipped gated on custom_tools, so an agent whose only
  # tools were the agenda got none of it. On a booking agent that gap reads as
  # an invented time, which sends somebody to a salon not expecting them.
  describe 'discipline for the agenda tools' do
    def prompt_for(assistant)
      described_class.new(conversation: conversation, assistant: assistant)
                     .send(:system_prompt_segments).join("\n")
    end

    def connect_calendar!
      connection = Ai::Calendar::Connection.create!(
        ai_assistant: assistant, account: account,
        google_email: 'salao@exemplo.com', encrypted_refresh_token: 'token'
      )
      Ai::Calendar::Professional.create!(
        connection: connection, ai_assistant: assistant, account: account,
        name: 'Agenda do salão', calendar_id: 'primary'
      )
      Ai::Calendar::Service.create!(
        ai_assistant: assistant, account: account, name: 'Progressiva', duration_minutes: 90
      )
    end

    it 'tells an agent with an agenda never to invent a time' do
      connect_calendar!

      expect(prompt_for(assistant)).to include('consultar_horarios').and include('AGENDA CONECTADA')
    end

    # No professional and no service means no booking tools, and a rule about
    # tools the model was never given is noise it has to read every turn.
    it 'says nothing about the agenda to an agent that has none' do
      expect(prompt_for(assistant)).not_to include('AGENDA CONECTADA')
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

    # The split is what lets Anthropic serve the bulk of the prompt from cache.
    # Nothing may be lost in the process: the joined segments must still be the
    # whole prompt.
    it 'splits the prompt into a cacheable stable half and a per-turn half' do
      stable, per_turn = service.send(:system_prompt_segments)

      expect(stable).to include('Persona:')
      expect(stable).not_to include('REGRA DE VERACIDADE')
      expect(per_turn).to include('REGRA DE VERACIDADE')
      expect(service.send(:build_system_prompt)).to include('Persona:').and include('REGRA DE VERACIDADE')
    end

    # WhatsApp marks bold with one asterisk; the model writes Markdown, and the
    # customer was seeing the asterisks instead of the price standing out.
    it 'converts markdown bold to the WhatsApp form' do
      expect(service.send(:whatsapp_markup, 'sai por **R$ 59,90** hoje')).to eq('sai por *R$ 59,90* hoje')
    end

    it 'leaves arithmetic and unmatched asterisks alone' do
      expect(service.send(:whatsapp_markup, '2 ** 3 e **isto nao fecha')).to eq('2 ** 3 e **isto nao fecha')
    end

    # Nobody types an em dash on a phone, so it reads as machine-written the
    # moment it lands. The prompt forbids it; this is what makes "never" true.
    it 'replaces the em dash the model reaches for' do
      expect(service.send(:whatsapp_markup, 'Shampoo Volume Control — limpa sem ressecar'))
        .to eq('Shampoo Volume Control, limpa sem ressecar')
    end

    # The blank line is where split_messages cuts one bubble from the next, so
    # eating it here would silently merge two messages into one.
    it 'never swallows the blank line that separates two messages' do
      expect(service.send(:whatsapp_markup, "primeira — parte\n\nsegunda parte"))
        .to eq("primeira, parte\n\nsegunda parte")
    end

    it 'ships the hard anti-fabrication rule in every system prompt' do
      prompt = service.send(:build_system_prompt)

      expect(prompt).to include('REGRA DE VERACIDADE')
      expect(prompt).to include('NUNCA invente preço')
    end
  end

  describe 'deterministic grounding check (verificação de saída)' do
    let(:service) { described_class.new(conversation: conversation, assistant: assistant) }

    def training(title, content)
      Ai::Training.create!(
        account: account, ai_assistant: assistant, title: title, content: content,
        source_type: 'text', category: 'catalog', status: 'ready'
      )
    end

    def reply(content)
      { content: content, model: 'claude' }
    end

    it 'lets a price through when it exists in the knowledge base' do
      training('Preços', 'Progressiva Premium: R$ 189,90.')
      allow(claude).to receive(:chat).and_return(reply('A Premium fica R$ 189,90. Quer que eu separe?'))

      expect(service.perform[:content]).to include('R$ 189,90')
    end

    it 'matches on digits, so formatting differences do not block a real price' do
      training('Preços', 'Progressiva Premium: R$189.90 no pix.')
      allow(claude).to receive(:chat).and_return(reply('Fica R$ 189,90 no pix. Quer que eu separe?'))

      expect(service.perform[:content]).to include('R$ 189,90')
    end

    it 'regenerates once when the reply invents a value, and returns the clean rewrite' do
      training('Preços', 'Progressiva Premium: R$ 189,90.')
      allow(claude).to receive(:chat).and_return(
        reply('A Premium fica R$ 250,00 hoje.'),
        reply('A Premium é a ideal pro seu caso. Deixa eu confirmar o valor e já te falo.')
      )

      result = service.perform

      expect(result[:content]).not_to include('250')
      expect(claude).to have_received(:chat).twice
    end

    it 'stays silent instead of quoting a value the operator never set' do
      training('Preços', 'Progressiva Premium: R$ 189,90.')
      allow(claude).to receive(:chat).and_return(reply('Sai por R$ 250,00 hoje.'))

      expect { service.perform }.to raise_error(described_class::UngroundedClaim)
    end

    it 'accepts a value the customer already quoted in the conversation' do
      create(:message, conversation: conversation, account: account, message_type: 'incoming',
                       content: 'vi que custa R$ 250,00, confere?')
      allow(claude).to receive(:chat).and_return(reply('Isso mesmo, R$ 250,00. Quer que eu separe?'))

      expect(service.perform[:content]).to include('R$ 250,00')
    end

    it 'ignores bare numbers that are not a commercial promise' do
      allow(claude).to receive(:chat).and_return(reply('São 2 aplicações e dura 3 meses. Quer que eu separe?'))

      result = service.perform

      expect(result[:content]).to include('2 aplicações')
      expect(claude).to have_received(:chat).once
    end

    it 'does not treat product copy like "100% sem formol" as a price claim' do
      allow(claude).to receive(:chat).and_return(reply('A Premium é 100% sem formol. Quer que eu separe?'))

      result = service.perform

      expect(result[:content]).to include('100% sem formol')
      expect(claude).to have_received(:chat).once
    end

    # Otherwise the guard goes blind exactly on the repeat offence: a value the
    # bot invented last turn would justify itself this turn.
    it 'does not accept a value the bot itself invented in a previous reply' do
      create(:message, conversation: conversation, account: account, message_type: 'outgoing',
                       content: 'Fica R$ 250,00.').update!(sender: nil)
      allow(claude).to receive(:chat).and_return(reply('Confirmando, sai por R$ 250,00.'))

      expect { service.perform }.to raise_error(described_class::UngroundedClaim)
    end

    it 'skips the check after a booking so the confirmation is never dropped' do
      allow(claude).to receive(:chat).and_return(reply('Agendado! Fica R$ 250,00 no dia 20.'))
      service.instance_variable_set(:@performed_external_write, true)

      expect(service.perform[:content]).to include('R$ 250,00')
    end

    # The operator answering from their own phone lands as outgoing WITH NO
    # SENDER, exactly like a bot post, so it needs the echo carve-out.
    it 'accepts a value the operator quoted by hand from their own phone' do
      create(:message, conversation: conversation, account: account, message_type: 'outgoing',
                       content: 'Fica R$ 250,00.',
                       content_attributes: { external_echo: true }).update!(sender: nil)
      allow(claude).to receive(:chat).and_return(reply('Isso mesmo, R$ 250,00. Quer que eu separe?'))

      expect(service.perform[:content]).to include('R$ 250,00')
    end

    it 'still blocks a percentage that is a real commercial promise' do
      allow(claude).to receive(:chat).and_return(reply('Hoje tem 100% de desconto pra você.'))

      expect { service.perform }.to raise_error(described_class::UngroundedClaim)
    end
  end

  # Message carries `default_scope { order(created_at: :asc) }`, so a plain
  # `.order(created_at: :desc)` only APPENDS and the ascending key still wins:
  # `limit` then returns the OLDEST rows. Every ordered read here must use
  # `reorder`, or the agent reasons over the wrong end of the conversation.
  describe 'message ordering' do
    it 'feeds Claude the conversation in chronological order' do
      conv = create(:conversation, account: account)
      create(:message, conversation: conv, account: account, message_type: 'incoming',
                       content: 'primeira', created_at: 5.minutes.ago)
      create(:message, conversation: conv, account: account, message_type: 'outgoing',
                       content: 'resposta do meio', created_at: 3.minutes.ago)
      create(:message, conversation: conv, account: account, message_type: 'incoming',
                       content: 'ultima', created_at: 1.minute.ago)

      msgs = described_class.new(conversation: conv, assistant: assistant).send(:build_recent_messages)

      expect(msgs.first[:content]).to include('primeira')
      expect(msgs.last[:content]).to include('ultima')
    end

    it 'ranks knowledge against the LATEST customer message, not the oldest' do
      conv = create(:conversation, account: account)
      create(:message, conversation: conv, account: account, message_type: 'incoming',
                       content: 'oi tudo bem', created_at: 5.minutes.ago)
      create(:message, conversation: conv, account: account, message_type: 'incoming',
                       content: 'me fala mais', created_at: 3.minutes.ago)
      create(:message, conversation: conv, account: account, message_type: 'incoming',
                       content: 'qual o preço da progressiva', created_at: 1.minute.ago)

      query = described_class.new(conversation: conv, assistant: assistant).send(:knowledge_query)

      expect(query).to include('progressiva')
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
      executor = instance_double(Ai::Agent::CompositeExecutor, performed_write?: true, definitions: [])
      loop_service = instance_double(Ai::Agent::ToolLoopService, perform: { content: 'ok' },
                                                                tool_calls: [], tool_results: [])
      allow(Ai::Agent::ToolLoopService).to receive(:new).and_return(loop_service)

      service.send(:run_own_tool_loop, [], executor)

      expect(service.instance_variable_get(:@performed_external_write)).to be(true)
    end
  end

  describe 'workspace integrations (custom tools)' do
    it 'routes to its own tool loop, separate from belezaki, when the agent has integrations' do
      service = described_class.new(conversation: conversation, assistant: assistant)
      Ai::CustomTool.create!(ai_assistant: assistant, account: account, title: 'Buscar', slug: 'buscar',
                             endpoint_url: 'https://loja.example.com/api', http_method: 'GET',
                             auth_type: 'none', param_schema: [])
      allow(Ai::Agent::ToolLoopService).to receive(:new)
        .and_return(instance_double(Ai::Agent::ToolLoopService, perform: { content: 'ok' },
                                                               tool_calls: [], tool_results: []))
      allow(Ai::CustomToolExecutor).to receive(:new).and_call_original

      expect(service.send(:generate_response, [])).to eq(content: 'ok')
      expect(Ai::CustomToolExecutor).to have_received(:new)
    end
  end

  describe 'belezaki is opt-in per agent' do
    def tool_names(subject_assistant)
      described_class.new(conversation: conversation, assistant: subject_assistant)
                     .send(:own_tools).definitions.map { |definition| definition[:name] }
    end

    # The whole reason this module exists: a LINKED ACCOUNT used to switch
    # scheduling on for every one of its agents, putting five tool schemas in
    # every turn of agents that book nothing.
    it 'offers no belezaki tool to an agent that has not connected one' do
      allow(Ai::Belezaki::TenantResolver).to receive(:external_id).and_return('ext-1')

      expect(tool_names(assistant)).not_to include('sugerir_dias', 'listar_profissionais')
    end

    it 'offers them once THIS agent is connected' do
      Ai::Belezaki::Connection.create!(ai_assistant: assistant, account: account, external_id: 'ext-1')

      expect(tool_names(assistant)).to include('sugerir_dias', 'agendar')
    end

    # A revoked connection is not a connection: the agent must stop offering
    # times it can no longer verify.
    it 'stops offering them when the connection is revoked' do
      connection = Ai::Belezaki::Connection.create!(ai_assistant: assistant, account: account, external_id: 'ext-1')
      connection.revoke!('token rejected')

      expect(tool_names(assistant.reload)).not_to include('agendar')
    end

    # Tools without discipline is exactly what produced a confirmed appointment
    # that never existed on the Google side.
    it 'ships the salon agenda rules to a connected agent' do
      Ai::Belezaki::Connection.create!(ai_assistant: assistant, account: account, external_id: 'ext-1')

      prompt = described_class.new(conversation: conversation, assistant: assistant)
                              .send(:system_prompt_segments).join("\n")

      expect(prompt).to include('AGENDA DO SALÃO CONECTADA')
      # The two things it cannot see and must therefore never claim.
      expect(prompt).to include('NUNCA diga que enviou confirmação no WhatsApp')
    end

    it 'says nothing about the salon agenda to an agent without one' do
      prompt = described_class.new(conversation: conversation, assistant: assistant)
                              .send(:system_prompt_segments).join("\n")

      expect(prompt).not_to include('AGENDA DO SALÃO CONECTADA')
    end

    # The frozen id is the point: resolving the account again on every reply is
    # what could move a live agent onto another salon's agenda.
    it 'builds the client from the connection id, not by resolving the account' do
      Ai::Belezaki::Connection.create!(ai_assistant: assistant, account: account, external_id: 'ext-frozen')
      allow(Ai::Belezaki::TenantResolver).to receive(:external_id).and_return('ext-other')
      allow(Ai::Belezaki::AgentClient).to receive(:new).and_call_original

      described_class.new(conversation: conversation, assistant: assistant).send(:belezaki_executor)

      expect(Ai::Belezaki::AgentClient).to have_received(:new).with(external_id: 'ext-frozen')
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
