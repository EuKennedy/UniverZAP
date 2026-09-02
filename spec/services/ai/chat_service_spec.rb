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

  it 'locks the copilot role and drops the customer sales tone' do
    captured = nil
    allow(claude).to receive(:chat) do |**kwargs|
      captured = kwargs[:system]
      { content: 'No que posso ajudar?', model: 'claude' }
    end

    described_class.new(thread: thread, user_message: 'olá consegue me ajudar?').perform

    expect(captured).to include('COPILOTO INTERNO')
    expect(captured).to include('NUNCA com o cliente')
    expect(captured).not_to include('foco em conversão')
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
    let(:loop_service) { instance_double(Ai::Agent::ToolLoopService) }

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
