# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::CustomerSignalAuditJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  def reply_invocation(created_at: 2.minutes.ago)
    delivered = create(:message, conversation: conversation, account: account, message_type: 'outgoing',
                                 content: 'Fica R$ 189,90.')
    create(:ai_invocation, account: account, ai_assistant: assistant, phase: 'autopilot',
                           conversation_id: conversation.id, message_id: delivered.id,
                           created_at: created_at)
  end

  def complaint(text)
    create(:message, conversation: conversation, account: account, message_type: 'incoming', content: text)
  end

  describe 'detection' do
    it 'flags the preceding reply when the customer pushes back' do
      invocation = reply_invocation

      described_class.perform_now(complaint('não é isso, tá errado').id)

      expect(invocation.reload.auto_flag).to eq('cliente_insatisfeito')
    end

    it 'keeps the flag in the auto_flags list alongside an earlier one' do
      invocation = reply_invocation
      invocation.update!(auto_flags: ['sem_fonte'], auto_flag: 'sem_fonte')

      described_class.perform_now(complaint('nada a ver').id)

      expect(invocation.reload.auto_flags).to contain_exactly('sem_fonte', 'cliente_insatisfeito')
    end

    # Severity order: the complaint outranks a soft "no source" note.
    it 'promotes the complaint to the primary flag' do
      invocation = reply_invocation
      invocation.update!(auto_flags: ['baixa_confianca'], auto_flag: 'baixa_confianca')

      described_class.perform_now(complaint('quero falar com um atendente').id)

      expect(invocation.reload.auto_flag).to eq('cliente_insatisfeito')
    end

    it 'ignores an ordinary reply from the customer' do
      invocation = reply_invocation

      described_class.perform_now(complaint('perfeito, obrigado!').id)

      expect(invocation.reload.auto_flag).to be_nil
    end
  end

  describe 'scoping' do
    # A human operator routinely takes over mid-conversation. If they answered
    # after the bot did, the complaint is about the human, and blaming the bot's
    # earlier reply would put a correct answer in the review queue.
    it 'does not blame the bot when a human answered after it' do
      invocation = reply_invocation
      agent = create(:user, account: account, role: :agent)
      create(:message, conversation: conversation, account: account, message_type: 'outgoing',
                       content: 'Na verdade fica R$ 250,00.', sender: agent)

      described_class.perform_now(complaint('tá errado').id)

      expect(invocation.reload.auto_flag).to be_nil
    end

    it 'ignores a reply older than the lookback window' do
      invocation = reply_invocation(created_at: (described_class::LOOKBACK + 1.hour).ago)

      described_class.perform_now(complaint('tá errado').id)

      expect(invocation.reload.auto_flag).to be_nil
    end

    it 'does nothing when the conversation has no logged reply' do
      expect { described_class.perform_now(complaint('tá errado').id) }.not_to raise_error
    end

    it 'does nothing when the message no longer exists' do
      expect { described_class.perform_now(-1) }.not_to raise_error
    end
  end
end
