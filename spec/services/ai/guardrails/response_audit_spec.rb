# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Guardrails::ResponseAudit do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def audit(**overrides)
    described_class.new(
      **{ conversation: conversation, reply: 'ok', user_message: 'oi', chunks: [{ 'title' => 'x' }] }
      .merge(overrides)
    ).perform
  end

  describe 'preco_inventado' do
    it 'flags a reply the grounding check had to regenerate' do
      expect(audit(ungrounded: true)).to include('preco_inventado')
    end

    it 'stays quiet when the grounding check never fired' do
      expect(audit(ungrounded: false)).not_to include('preco_inventado')
    end
  end

  describe 'baixa_confianca' do
    it 'flags a self-assessment below the floor' do
      expect(audit(confidence: 0.4)).to include('baixa_confianca')
    end

    it 'does not flag at the floor' do
      expect(audit(confidence: described_class::CONFIDENCE_FLOOR)).not_to include('baixa_confianca')
    end

    it 'does not flag when the model gave no self-assessment' do
      expect(audit(confidence: nil)).not_to include('baixa_confianca')
    end
  end

  describe 'sem_fonte' do
    it 'flags a factual question answered with nothing retrieved' do
      expect(audit(chunks: [], user_message: 'quanto custa a progressiva?')).to include('sem_fonte')
    end

    it 'ignores small talk answered with nothing retrieved' do
      expect(audit(chunks: [], user_message: 'bom dia')).not_to include('sem_fonte')
    end

    it 'ignores a factual question that did retrieve something' do
      expect(audit(user_message: 'quanto custa?')).not_to include('sem_fonte')
    end

    # An agent with no base at all would flag every reply, and a queue that is
    # 100% one message stops being read. That belongs in onboarding.
    it 'stays silent for an agent that has no knowledge base yet' do
      expect(audit(chunks: [], user_message: 'quanto custa?', knowledge_available: false))
        .not_to include('sem_fonte')
    end
  end

  describe 'promessa_solta' do
    it 'flags a booking the agent claims to have made without writing anywhere' do
      expect(audit(reply: 'Pronto, já agendei pra sexta às 14h.')).to include('promessa_solta')
    end

    it 'stays quiet when the agent really did write to the external system' do
      expect(audit(reply: 'Pronto, já agendei pra sexta às 14h.', performed_write: true))
        .not_to include('promessa_solta')
    end

    # Sending a link is within the agent's own power, so it is not a promise it
    # cannot keep.
    it 'does not flag ordinary follow-through' do
      expect(audit(reply: 'Te mando o link agora.')).not_to include('promessa_solta')
    end

    # An offer is not a promise. Treating every one as such would flag half of a
    # healthy sales conversation.
    it 'does not flag an offer to schedule' do
      expect(audit(reply: 'Posso agendar pra você na sexta?')).not_to include('promessa_solta')
    end
  end

  describe 'horario_divergente' do
    before do
      inbox.update!(working_hours_enabled: true)
      inbox.working_hours.find_by(day_of_week: 0)&.update!(closed_all_day: true)
    end

    it 'flags a claim of being open on a day the inbox is closed all day' do
      expect(audit(reply: 'Pode vir domingo que a gente atende normal.'))
        .to include('horario_divergente')
    end

    it 'does not flag the correct answer about the same day' do
      expect(audit(reply: 'Domingo a gente não atende, fechamos.'))
        .not_to include('horario_divergente')
    end

    it 'does not flag a day the inbox is open' do
      expect(audit(reply: 'Atendemos na quarta sem problema.'))
        .not_to include('horario_divergente')
    end

    # A blanket "does the sentence contain não?" used to read this as a denial,
    # so the exact mistake the guardrail exists to catch was the one it missed.
    it 'flags an affirmation that merely happens to contain a negation' do
      expect(audit(reply: 'Não se preocupe, atendemos domingo sim, é só chegar!'))
        .to include('horario_divergente')
    end

    it 'flags a range that covers the closed day' do
      inbox.working_hours.find_by(day_of_week: 3).update!(
        closed_all_day: true, open_hour: nil, open_minutes: nil, close_hour: nil, close_minutes: nil
      )

      expect(audit(reply: 'Atendemos de segunda a sexta, das 9h às 18h.'))
        .to include('horario_divergente')
    end

    it 'does not flag a range that avoids the closed day' do
      expect(audit(reply: 'Atendemos de segunda a sexta, das 9h às 18h.'))
        .not_to include('horario_divergente')
    end

    it 'stays silent when the operator never configured working hours' do
      inbox.update!(working_hours_enabled: false)

      expect(audit(reply: 'Pode vir domingo que a gente atende normal.'))
        .not_to include('horario_divergente')
    end
  end

  describe 'severity' do
    it 'orders flags so the worst problem is first' do
      flags = audit(reply: 'já agendei', ungrounded: true, confidence: 0.1, chunks: [],
                    user_message: 'quanto custa?')

      expect(Ai::Invocation.primary_flag(flags)).to eq('preco_inventado')
    end
  end

  it 'never raises: an audit is not worth losing a reply over' do
    allow(conversation).to receive(:inbox).and_raise(StandardError, 'boom')

    expect { audit }.not_to raise_error
  end
end
