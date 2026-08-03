# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::FeedbackApplicationService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:invocation) do
    create(:ai_invocation, account: account, ai_assistant: assistant, phase: 'autopilot',
                           user_message: 'quanto custa a progressiva sem formol?',
                           ai_response: 'Fica R$ 999,00.')
  end

  def feedback(reason:, text: 'A progressiva sem formol fica R$ 189,90.', rating: 'down')
    create(:ai_response_feedback, account: account, ai_assistant: assistant,
                                  ai_invocation: invocation, reviewer: admin,
                                  rating: rating, reason: reason, corrected_text: text)
  end

  describe 'facts become knowledge the very next turn' do
    it 'turns a wrong price into a catalogue document' do
      record = feedback(reason: 'preco_inventado')

      described_class.new(feedback: record).perform

      training = record.reload.ai_training
      expect(training.category).to eq('catalog')
      expect(training.status).to eq('ready')
      expect(training.content).to include('R$ 189,90')
    end

    it 'turns wrong information into an FAQ document' do
      record = feedback(reason: 'info_incorreta')

      described_class.new(feedback: record).perform

      expect(record.reload.ai_training.category).to eq('faq')
    end

    it 'keeps the question so the document is retrievable by how the customer asked' do
      record = feedback(reason: 'info_incorreta')

      described_class.new(feedback: record).perform

      expect(record.reload.ai_training.content).to include('quanto custa a progressiva sem formol?')
    end

    # Retrieval is lexical, so the rejected wording is often the closest match
    # to how the customer will ask again. The document that comes back then
    # carries the correction with it.
    it 'records what the agent must never say again' do
      record = feedback(reason: 'info_incorreta')

      described_class.new(feedback: record).perform

      expect(record.reload.ai_training.content).to include('Nunca responda assim').and include('R$ 999,00')
    end

    it 'stamps when it was applied' do
      record = feedback(reason: 'preco_inventado')

      described_class.new(feedback: record).perform

      expect(record.reload).to be_applied
    end
  end

  describe 'handoff becomes a rule' do
    it 'creates an escalation intent with the distinctive words as triggers' do
      record = feedback(reason: 'deveria_transbordar', text: 'Chamar a gerente para desconto acima de 20%.')

      described_class.new(feedback: record).perform

      intent = record.reload.ai_intent
      expect(intent.action).to eq('escalate_human')
      expect(intent.trigger_list).to include('progressiva')
      expect(intent.trigger_list).not_to include('quanto')
    end
  end

  describe 'what is deliberately NOT applied' do
    # Tone changes how the agent behaves in every conversation, so it only goes
    # live through a prompt version that was A/B tested first.
    it 'refuses a tone correction' do
      record = feedback(reason: 'tom_inadequado', text: 'Fale mais curto.')

      expect { described_class.new(feedback: record).perform }
        .to raise_error(described_class::NotApplicable)
      expect(record.reload).not_to be_applied
    end

    it 'refuses a correction with no corrected text' do
      record = feedback(reason: 'info_incorreta', text: nil)

      expect { described_class.new(feedback: record).perform }
        .to raise_error(described_class::NotApplicable)
    end

    it 'refuses a thumbs up' do
      record = feedback(reason: nil, rating: 'up', text: nil)

      expect { described_class.new(feedback: record).perform }
        .to raise_error(described_class::NotApplicable)
    end
  end

  describe 'tenant scoping' do
    it 'creates the document inside the agent account, never anywhere else' do
      record = feedback(reason: 'info_incorreta')

      described_class.new(feedback: record).perform

      expect(record.reload.ai_training.account_id).to eq(account.id)
    end
  end
end
