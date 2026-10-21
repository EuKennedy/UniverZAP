# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Broadcasts::VariationSuggestionService do
  let(:account) { create(:account) }
  let(:claude) { instance_double(Ai::ClaudeService) }

  before do
    allow(Ai::ClaudeService).to receive(:new).and_return(claude)
  end

  it 'separa as versões e registra a fase própria' do
    allow(claude).to receive(:chat).and_return(content: "Oi {primeiro_nome}!\n---\nOlá {primeiro_nome}!\n---\n\"E aí {primeiro_nome}?\"")

    expect(described_class.new(account: account, text: 'Oie {primeiro_nome}').perform)
      .to eq(['Oi {primeiro_nome}!', 'Olá {primeiro_nome}!', 'E aí {primeiro_nome}?'])
    expect(claude).to have_received(:chat).with(hash_including(phase: 'broadcast_variations'))
    expect(Ai::Invocation::PHASES).to include('broadcast_variations')
  end
end
