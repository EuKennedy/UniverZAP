# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Guardrails::CustomerSignal do
  describe '.dissatisfied?' do
    it 'reads a direct correction' do
      expect(described_class).to be_dissatisfied('não é isso que eu perguntei')
    end

    it 'reads "tá errado"' do
      expect(described_class).to be_dissatisfied('esse preço tá errado')
    end

    # The most natural phrasing in Brazilian Portuguese uses the definite
    # article, and a pattern that only allowed "um/uma" missed the strongest
    # signal the module can receive in its most common form.
    it 'reads a request for a human with a definite article' do
      expect(described_class).to be_dissatisfied('quero falar com a atendente')
    end

    it 'reads a request to be transferred' do
      expect(described_class).to be_dissatisfied('me passa pra um humano')
    end

    it 'ignores an ordinary reply' do
      expect(described_class).not_to be_dissatisfied('perfeito, obrigada!')
    end

    # In the beauty vertical this is overwhelmingly the customer describing
    # their own problem, which is the opposite of a complaint about the agent.
    it 'ignores a customer describing their own problem as terrible' do
      expect(described_class)
        .not_to be_dissatisfied('meu cabelo tá péssimo depois da progressiva que fiz em outro salão')
    end

    it 'ignores a compliment that mentions a service word' do
      expect(described_class).not_to be_dissatisfied('adorei o atendimento, muito obrigada')
    end
  end
end
