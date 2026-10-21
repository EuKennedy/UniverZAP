require 'rails_helper'

RSpec.describe Whatsapp::StatusPosts::SuggestionService do
  let(:account) { create(:account, name: 'Studio Bella') }

  it 'is a phase the cost ledger accepts' do
    expect(Ai::Invocation::PHASES).to include(described_class::PHASE)
  end

  it 'asks the account assistant and returns clean text' do
    # Toda conta nasce com o assistente de atendimento; é ele que a sugestão usa.
    assistant = account.ai_assistants.active.order(:id).first
    content = "\"Sábado tem horário! Chama no WhatsApp\"\n---\n2. Sábado livre!\n---\nCorre que sábado enche!\n---\nquarta sobra"
    claude = instance_double(Ai::ClaudeService, chat: { content: content })
    allow(Ai::ClaudeService).to receive(:new).with(assistant: assistant).and_return(claude)

    texts = described_class.new(account: account, prompt: 'agenda de sábado', tone: 'urgent').perform

    expect(texts).to eq(['Sábado tem horário! Chama no WhatsApp', 'Sábado livre!', 'Corre que sábado enche!'])
    expect(claude).to have_received(:chat).with(hash_including(phase: 'status_suggestion',
                                                               system: a_string_including('Studio Bella', 'urgência')))
  end

  it 'needs a subject or a draft' do
    expect { described_class.new(account: account, prompt: ' ').perform }.to raise_error(Ai::ClaudeService::Error)
  end
end
