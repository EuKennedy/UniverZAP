require 'rails_helper'

RSpec.describe Ai::Agent::Toolset do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  def names(toolset)
    toolset.executor.definitions.map { |definition| definition[:name] }
  end

  def custom_tool!
    Ai::CustomTool.create!(ai_assistant: assistant, account: account, title: 'Rastreio', slug: 'rastreio',
                           endpoint_url: 'https://loja.example.com/api', http_method: 'GET',
                           auth_type: 'none', param_schema: [])
  end

  it 'não oferece nada para um agente sem ferramenta e sem agenda' do
    expect(names(described_class.new(assistant: assistant, conversation: conversation))).to be_empty
  end

  it 'oferece as ferramentas customizadas do agente' do
    custom_tool!

    expect(names(described_class.new(assistant: assistant, conversation: conversation))).to include('rastreio')
  end

  # O widget: uma thread aberta fora de uma conversa é legítima, e ferramenta
  # customizada não precisa de contato nenhum para funcionar.
  it 'entrega as customizadas mesmo sem conversa' do
    custom_tool!

    expect(names(described_class.new(assistant: assistant))).to include('rastreio')
  end

  describe 'com a agenda do salão conectada' do
    before { Ai::Belezaki::Connection.create!(ai_assistant: assistant, account: account, external_id: 'ext-frozen') }

    it 'oferece as ferramentas de agenda quando há conversa' do
      expect(names(described_class.new(assistant: assistant, conversation: conversation))).to include('agendar')
    end

    # Agendar sem contato é o agendamento órfão que Ai::Belezaki::CustomerPhone
    # documenta: chave de idempotência inútil, cliente que nunca acha o próprio
    # horário, confirmação morrendo em silêncio.
    it 'deixa a agenda de fora quando não há conversa' do
      expect(names(described_class.new(assistant: assistant))).not_to include('agendar')
    end

    # A extração para cá perdeu o `conversation:` que o AutopilotReplyService
    # passava, e um agendamento gravado sem ele não deixa rastro nenhum do nosso
    # lado: o salão confirma a venda e não há como dizer de qual conversa ela veio.
    it 'atribui o agendamento à conversa que o produziu' do
      allow(Ai::Belezaki::SchedulingTools).to receive(:new).and_call_original

      described_class.new(assistant: assistant, conversation: conversation).executor.definitions

      expect(Ai::Belezaki::SchedulingTools).to have_received(:new)
        .with(anything, hash_including(conversation: conversation))
    end

    # O id congelado é o ponto: resolver a conta de novo a cada resposta é o que
    # poderia mover um agente vivo para a agenda de outro salão.
    it 'monta o cliente pelo id da conexão, e não resolvendo a conta' do
      allow(Ai::Belezaki::TenantResolver).to receive(:external_id).and_return('ext-other')
      allow(Ai::Belezaki::AgentClient).to receive(:new).and_call_original

      described_class.new(assistant: assistant, conversation: conversation).executor.definitions

      expect(Ai::Belezaki::AgentClient).to have_received(:new).with(external_id: 'ext-frozen')
    end
  end
end
