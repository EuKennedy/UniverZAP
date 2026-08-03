# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AbReplayService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:version) do
    create(:ai_prompt_version, ai_assistant: assistant, account: account,
                               system_prompt: 'Seja direto e cite o preço.')
  end
  let(:invocation) do
    create(:ai_invocation, account: account, ai_assistant: assistant, phase: 'autopilot',
                           conversation_id: conversation.id,
                           user_message: 'quanto custa a progressiva?',
                           ai_response: 'Fica R$ 189,90.', cost_brl: 0.02, duration_ms: 1500)
  end
  let(:claude) { instance_double(Ai::ClaudeService) }

  before do
    allow(Ai::ClaudeService).to receive(:new).and_return(claude)
    create(:ai_training, ai_assistant: assistant, title: 'Preços',
                         content: 'Progressiva R$ 189,90', status: 'ready')
  end

  def claude_answers(text)
    allow(claude).to receive(:chat).and_return({ content: text, model: 'claude-sonnet-4-5' })
  end

  describe 'isolation from customers' do
    # A replay that could reach a customer would make the lab unusable on a
    # live account, which is the only account with questions worth replaying.
    it 'never creates a message' do
      claude_answers('Fica R$ 189,90 no Pix.')

      expect { described_class.new(invocation: invocation, version: version).perform }
        .not_to(change { conversation.messages.count })
    end

    # Polluting the supervision queue with answers nobody received would make
    # the queue lie about what customers actually saw.
    it 'does not write a response-log row for the candidate' do
      claude_answers('Fica R$ 189,90.')

      described_class.new(invocation: invocation, version: version).perform

      expect(claude).to have_received(:chat).with(hash_excluding(:log_context))
    end

    # Lab spend is real spend, but it is not the cost of serving customers.
    # Charging the ROI panel for it would punish the operator who tests before
    # shipping.
    it 'bills the replay under its own phase so ROI stays about customers' do
      claude_answers('ok')

      described_class.new(invocation: invocation, version: version).perform

      expect(claude).to have_received(:chat).with(hash_including(phase: 'replay'))
    end

    # A duel that capped the candidate at a different length would measure an
    # agent that is not the one that would go live, and length is most of what a
    # reviewer is judging.
    it 'does not override the length the agent is configured for' do
      claude_answers('ok')

      described_class.new(invocation: invocation, version: version).perform

      expect(claude).to have_received(:chat).with(hash_excluding(:max_tokens))
    end
  end

  describe 'the duel' do
    it 'asks the candidate the same question the customer asked' do
      claude_answers('Fica R$ 189,90.')

      described_class.new(invocation: invocation, version: version).perform

      expect(claude).to have_received(:chat)
        .with(hash_including(messages: [{ role: 'user', content: 'quanto custa a progressiva?' }]))
    end

    it 'runs the candidate on its own instructions' do
      claude_answers('ok')

      described_class.new(invocation: invocation, version: version).perform

      expect(claude).to have_received(:chat)
        .with(hash_including(system: a_string_including('Seja direto e cite o preço.')))
    end

    it 'strips the internal meta block from the candidate answer' do
      claude_answers(%(Fica R$ 189,90.\n<meta>{"confidence":0.9}</meta>))

      comparison = described_class.new(invocation: invocation, version: version).perform

      expect(comparison.response_b).to eq('Fica R$ 189,90.')
      expect(comparison.telemetry_b['confidence']).to eq(0.9)
    end
  end

  describe 'the candidate is held to the same bar as production' do
    it 'marks a fabricated value as a critical loss' do
      claude_answers('Fica R$ 4.999,00 com desconto.')

      comparison = described_class.new(invocation: invocation, version: version).perform

      expect(comparison.critical_loss).to be(true)
    end

    it 'does not flag a value that is in the knowledge base' do
      claude_answers('Fica R$ 189,90.')

      comparison = described_class.new(invocation: invocation, version: version).perform

      expect(comparison.critical_loss).to be(false)
    end
  end

  describe 'idempotency' do
    it 'refuses to duel the same reply against the same version twice' do
      claude_answers('ok')
      described_class.new(invocation: invocation, version: version).perform

      expect { described_class.new(invocation: invocation, version: version).perform }
        .to raise_error(described_class::AlreadyCompared)
    end
  end
end
