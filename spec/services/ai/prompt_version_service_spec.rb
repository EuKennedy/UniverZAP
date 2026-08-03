# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::PromptVersionService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:ai_assistant, account: account, system_prompt: 'Venda progressivas.') }
  let(:service) { described_class.new(assistant: assistant, user: admin) }

  describe 'the first version changes nothing' do
    # Adopting versioning must not change a single reply. The first draft is a
    # verbatim copy of what the agent already runs.
    it 'copies the instructions the agent is already running' do
      expect(service.create_draft.system_prompt).to eq('Venda progressivas.')
    end

    it 'numbers versions in a way a human can say out loud' do
      expect(service.create_draft.version).to eq('v1')
      expect(service.create_draft.version).to eq('v2')
    end
  end

  describe 'learning carried into a draft' do
    it 'turns replies marked ideal into few-shot examples' do
      invocation = create(:ai_invocation, account: account, ai_assistant: assistant,
                                          user_message: 'faz sobrancelha?', ai_response: 'Fazemos sim!')
      create(:ai_response_feedback, account: account, ai_assistant: assistant,
                                    ai_invocation: invocation, reviewer: admin, rating: 'ideal')

      draft = service.create_draft

      expect(draft.few_shot_pairs.first).to eq('question' => 'faz sobrancelha?', 'answer' => 'Fazemos sim!')
    end

    # Past a handful the examples stop teaching a pattern and start dominating
    # the prompt, and the model recites them instead of answering.
    it 'caps the examples' do
      (Ai::PromptVersion::MAX_FEW_SHOTS + 4).times do
        invocation = create(:ai_invocation, account: account, ai_assistant: assistant,
                                            user_message: 'oi', ai_response: 'olá')
        create(:ai_response_feedback, account: account, ai_assistant: assistant,
                                      ai_invocation: invocation, reviewer: admin, rating: 'ideal')
      end

      expect(service.create_draft.few_shot_pairs.length).to eq(Ai::PromptVersion::MAX_FEW_SHOTS)
    end
  end

  describe 'promotion' do
    let(:candidate) { service.create_draft }

    it 'refuses a candidate that has not met the criteria' do
      expect { service.promote!(candidate) }.to raise_error(described_class::NotPromotable)
      expect(candidate.reload.status).to eq('draft')
    end

    context 'when the criteria are met' do
      before { allow_any_instance_of(Ai::PromotionPolicy).to receive(:promotable?).and_return(true) } # rubocop:disable RSpec/AnyInstance

      it 'puts the candidate live' do
        service.promote!(candidate)

        expect(assistant.reload.live_prompt_version).to eq(candidate)
      end

      # Two live versions would make "which prompt answered this?" unanswerable
      # exactly when it matters.
      it 'archives the outgoing version instead of leaving two live' do
        first = service.create_draft
        service.promote!(first)
        second = service.create_draft
        service.promote!(second)

        expect(assistant.prompt_versions.live.count).to eq(1)
        expect(first.reload.status).to eq('archived')
      end

      it 'changes what the agent actually runs on' do
        candidate.update!(system_prompt: 'Nova instrução.')

        service.promote!(candidate)

        expect(assistant.reload.effective_system_prompt).to eq('Nova instrução.')
      end
    end
  end

  describe 'rollback' do
    before { allow_any_instance_of(Ai::PromotionPolicy).to receive(:promotable?).and_return(true) } # rubocop:disable RSpec/AnyInstance

    # The whole value of rollback is that it works when everything else is
    # going wrong, so it is deliberately not gated on the promotion criteria.
    it 'returns to the previous version in one call' do
      first = service.create_draft
      service.promote!(first)
      second = service.create_draft
      service.promote!(second)

      service.rollback!

      expect(assistant.reload.live_prompt_version).to eq(first)
    end

    it 'refuses when there is nothing to return to' do
      expect { service.rollback! }.to raise_error(described_class::NothingToRollBackTo)
    end
  end

  describe 'an unversioned agent' do
    it 'keeps answering from the mutable column' do
      expect(assistant.effective_system_prompt).to eq('Venda progressivas.')
      expect(assistant.effective_few_shots).to be_empty
    end
  end
end
