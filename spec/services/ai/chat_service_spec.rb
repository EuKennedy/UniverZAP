require 'rails_helper'

RSpec.describe Ai::ChatService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:assistant) { create(:ai_assistant, account: account, tone: 'sales') }
  let(:claude) { instance_double(Ai::ClaudeService) }
  let(:thread) do
    Ai::ChatThread.create!(account: account, user: user, ai_assistant: assistant, title: 'Test')
  end

  before { allow(Ai::ClaudeService).to receive(:new).and_return(claude) }

  def capture_system(message: 'olá consegue me ajudar?')
    captured = nil
    allow(claude).to receive(:chat) do |**kwargs|
      captured = kwargs[:system]
      { content: 'No que posso ajudar?', model: 'claude' }
    end
    described_class.new(thread: thread, user_message: message).perform
    captured
  end

  it 'locks the copilot role and drops the customer sales tone' do
    prompt = capture_system.join("\n\n")

    expect(prompt).to include('COPILOTO INTERNO')
    expect(prompt).to include('NUNCA com o cliente')
    expect(prompt).not_to include('foco em conversão')
  end

  # O Guia é outro agente dentro do mesmo serviço: ele fala do PRODUTO com quem
  # usa o sistema, não da conversa do cliente com a atendente.
  describe 'o Guia do wiki' do
    let(:guia) do
      create(:ai_assistant, account: account, purpose: 'wiki',
                            system_prompt: 'Você é o Guia, o assistente do UniverZAP.')
    end
    let(:guia_thread) do
      Ai::ChatThread.create!(account: account, user: user, ai_assistant: guia, title: 'Ajuda')
    end

    def manual!(title, content)
      Ai::Training.create!(account: account, ai_assistant: guia, title: title, content: content,
                           source_type: 'text', category: 'base', status: 'ready')
    end

    def capture_guia_system(message: 'como conecto o whatsapp?')
      captured = nil
      allow(claude).to receive(:chat) do |**kwargs|
        captured = kwargs[:system]
        { content: 'Configurações → Caixas de entrada', model: 'claude' }
      end
      described_class.new(thread: guia_thread, user_message: message).perform
      captured
    end

    # O prompt do Guia mora em Ai::Wiki::Seeder e era descartado: ele recebia o
    # papel do copiloto e era mandado falar de uma conversa de cliente que não
    # existe na tela dele.
    it 'usa o prompt do próprio agente, e não o papel do copiloto' do
      prompt = capture_guia_system.join("\n\n")

      expect(prompt).to include('Você é o Guia')
      expect(prompt).not_to include('COPILOTO INTERNO')
    end

    # O manual inteiro são ~7.400 caracteres e a recuperação entregava ~3.300,
    # com boa parte de seção irrelevante: o ranking não tem limiar e preenche as
    # 8 vagas de qualquer jeito.
    it 'manda o manual inteiro, e não só o que a busca escolheu' do
      manual!('WhatsApp', 'Para conectar o WAHA, gere o QR code.')
      manual!('Campanhas', 'Dispare por template aprovado.')

      prompt = capture_guia_system(message: 'qualquer coisa').join("\n\n")

      expect(prompt).to include('gere o QR code').and include('template aprovado')
    end

    # O manual é igual em toda pergunta, então tem que ficar no bloco cacheado —
    # que é tudo menos o último segmento. Na cauda sobra a regra de estilo, de
    # duas linhas.
    it 'deixa o manual no bloco que o cache cobre' do
      manual!('WhatsApp', 'Para conectar o WAHA, gere o QR code.')

      segments = capture_guia_system

      expect(segments[0..-2].join("\n\n")).to include('gere o QR code')
      expect(segments.last).to eq(described_class::STYLE_RULE)
    end
  end

  # Segmentos e não string: Ai::ClaudeService manda string crua sem cache
  # nenhum, e o loop reenvia o prompt inteiro a cada iteração. O papel é igual
  # todo turno e tem que ficar ANTES do que muda, senão o breakpoint de cache
  # cai no lugar errado e o prefixo é recomprado inteiro a cada volta.
  it 'manda o prompt em segmentos, com o papel estável na frente' do
    Ai::Training.create!(account: account, ai_assistant: assistant, title: 'Tabela',
                         content: 'Progressiva Premium: R$ 189,90.', source_type: 'text',
                         category: 'catalog', status: 'ready')

    segments = capture_system(message: 'quanto custa a progressiva premium?')

    expect(segments).to be_an(Array)
    expect(segments.first).to include('COPILOTO INTERNO')
    expect(segments.last).to include('R$ 189,90')
  end

  it 'persists the user and assistant messages' do
    allow(claude).to receive(:chat).and_return({ content: 'ok', model: 'claude' })

    expect { described_class.new(thread: thread, user_message: 'oi').perform }
      .to change { thread.chat_messages.count }.by(2)
  end

  # O pedido que originou isto: o mesmo agente que monta carrinho e consulta
  # rastreio na conversa com o cliente ficava cego no widget, porque o copiloto
  # chamava o Claude direto, sem `tools:` e sem loop. Ele perguntava o código de
  # rastreio ao atendente em vez de consultar, por não ter com o quê.
  describe 'as ferramentas do agente' do
    # O serviço lê o gasto do turno depois do perform, para gravar tokens e reais
    # na mensagem — um dublê sem esses dois não representa mais o colaborador.
    let(:loop_service) do
      instance_double(Ai::Agent::ToolLoopService, spent_cents: 12.5, spent_tokens: [900, 120])
    end

    before do
      Ai::CustomTool.create!(ai_assistant: assistant, account: account, title: 'Rastreio',
                             slug: 'rastreio', endpoint_url: 'https://loja.example.com/api',
                             http_method: 'GET', auth_type: 'none', param_schema: [])
      allow(Ai::Agent::ToolLoopService).to receive(:new).and_return(loop_service)
      allow(loop_service).to receive(:perform).and_return({ content: 'Rastreio: a caminho.', model: 'claude' })
    end

    it 'passa as ferramentas do agente para o copiloto' do
      described_class.new(thread: thread, user_message: 'cadê o pedido dela?').perform

      expect(Ai::Agent::ToolLoopService).to have_received(:new)
        .with(hash_including(phase: 'copilot_chat', tools: be_present))
    end

    # Sem ferramenta nenhuma, o loop cobraria a máquina de nada: ele bilha por
    # iteração e uma chamada só resolve.
    it 'não monta o loop quando o agente não tem ferramenta' do
      Ai::CustomTool.destroy_all
      allow(claude).to receive(:chat).and_return({ content: 'oi', model: 'claude' })

      described_class.new(thread: thread, user_message: 'oi').perform

      expect(Ai::Agent::ToolLoopService).not_to have_received(:new)
    end
  end

  # Uma thread aberta fora de uma conversa é legítima, e agendar sem contato é o
  # agendamento órfão que Ai::Belezaki::CustomerPhone documenta.
  it 'responde mesmo sem conversa associada' do
    allow(claude).to receive(:chat).and_return({ content: 'oi', model: 'claude' })

    result = described_class.new(thread: thread, user_message: 'oi').perform

    expect(result[:content]).to eq('oi')
  end
end
