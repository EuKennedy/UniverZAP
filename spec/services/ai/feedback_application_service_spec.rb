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

    # The rejected answer must NOT be stored. This document becomes a sanctioned
    # source for the grounding guard, which compares digits only, so keeping the
    # fabricated price here would turn the correction that was meant to stop the
    # invention into the thing that made it permanently legitimate.
    it 'never stores the fabricated value it was correcting' do
      record = feedback(reason: 'preco_inventado')

      described_class.new(feedback: record).perform

      expect(record.reload.ai_training.content).not_to include('999')
    end

    it 'stamps when it was applied' do
      record = feedback(reason: 'preco_inventado')

      described_class.new(feedback: record).perform

      expect(record.reload).to be_applied
    end

    # An incoming message is not a source. A customer writing "vi por R$ 39,90"
    # would otherwise make 39,90 a value the agent may quote to every OTHER
    # customer, forever, because the document is a sanctioned source and the
    # guard compares digits only.
    it 'masks the digits of the customer question' do
      invocation.update!(user_message: 'vi que custa R$ 39,90, confirma?')
      record = feedback(reason: 'preco_inventado')

      described_class.new(feedback: record).perform

      content = record.reload.ai_training.content
      expect(content).not_to include('39,90')
      expect(content).to include('confirma')
    end

    # A reviewer who improves their own correction expects the agent to learn
    # the better version, not to keep competing with the wording they rejected.
    it 'updates the document it already created instead of adding a second one' do
      record = feedback(reason: 'info_incorreta')
      described_class.new(feedback: record).perform

      record.update!(corrected_text: 'Na verdade fica R$ 199,00.')
      expect { described_class.new(feedback: record).perform }
        .not_to change(Ai::Training, :count)
      expect(record.reload.ai_training.content).to include('R$ 199,00')
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
