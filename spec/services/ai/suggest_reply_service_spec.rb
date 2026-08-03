require 'rails_helper'

RSpec.describe Ai::SuggestReplyService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account, tone: 'sales') }
  let(:conversation) { create(:conversation, account: account) }
  let(:claude) { instance_double(Ai::ClaudeService) }
  let(:service) { described_class.new(conversation: conversation, assistant: assistant) }

  before do
    allow(Ai::ClaudeService).to receive(:new).and_return(claude)
    create(:message, conversation: conversation, account: account, message_type: 'incoming',
                     content: 'quanto custa a progressiva?', created_at: 1.minute.ago)
    create(:message, conversation: conversation, account: account, message_type: 'outgoing',
                     content: 'Já te falo.', created_at: 30.seconds.ago)
  end

  def training(title, content)
    Ai::Training.create!(
      account: account, ai_assistant: assistant, title: title, content: content,
      source_type: 'text', category: 'catalog', status: 'ready'
    )
  end

  def reply(content)
    { content: content, model: 'claude' }
  end

  # The suggestion is the text a HUMAN agent sends verbatim, so every guarantee
  # the autopilot has must hold here too.
  describe 'knowledge grounding' do
    it 'keeps a price that sits far beyond the old 280 char cut' do
      training('Tabela', "#{'blá ' * 200}A Progressiva Premium custa R$ 189,90 à vista.")

      expect(service.send(:knowledge_snippets)).to include('R$ 189,90')
    end

    it 'ships the anti-fabrication rule in the prompt' do
      expect(service.send(:build_system_prompt)).to include('REGRA DE VERACIDADE')
    end

    it 'lets a grounded price through' do
      training('Preços', 'Progressiva Premium: R$ 189,90.')
      allow(claude).to receive(:chat).and_return(reply('A Premium fica R$ 189,90.'))

      expect(service.perform[:content]).to include('R$ 189,90')
    end

    it 'regenerates once when the suggestion invents a value' do
      training('Preços', 'Progressiva Premium: R$ 189,90.')
      allow(claude).to receive(:chat).and_return(
        reply('Sai por R$ 250,00.'),
        reply('Deixa eu confirmar o valor certinho e já te falo.')
      )

      expect(service.perform[:content]).not_to include('250')
    end

    it 'refuses to hand the agent a price the operator never set' do
      training('Preços', 'Progressiva Premium: R$ 189,90.')
      allow(claude).to receive(:chat).and_return(reply('Sai por R$ 250,00.'))

      expect { service.perform }.to raise_error(described_class::UngroundedClaim)
    end
  end

  describe 'message ordering' do
    it 'sends the conversation in chronological order, newest last' do
      msgs = service.send(:build_messages)

      expect(msgs.first[:content]).to include('quanto custa')
      expect(msgs.last[:content]).to include('Já te falo')
    end
  end
end
