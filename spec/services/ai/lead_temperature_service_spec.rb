# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::LeadTemperatureService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, ai_assistant: assistant) }
  let(:claude) { instance_double(Ai::ClaudeService) }

  before do
    allow(Ai::ClaudeService).to receive(:new).and_return(claude)
    reader_says(intencao_compra: 0, urgencia: 0, objecao_forte: 0)
  end

  def reader_says(payload)
    body = {
      'intencao_compra' => payload[:intencao_compra], 'urgencia' => payload[:urgencia],
      'objecao_forte' => payload[:objecao_forte], 'interesse' => payload[:interesse].to_s,
      'valor_potencial' => payload[:valor_potencial].to_i,
      'motivo_bloqueio' => payload[:motivo_bloqueio].to_s, 'acao_sugerida' => 'ligar amanhã'
    }
    allow(claude).to receive(:chat).and_return({ content: body.to_json, model: 'haiku' })
  end

  def customer(text, at: Time.current)
    create(:message, conversation: conversation, account: account, message_type: 'incoming',
                     content: text, created_at: at)
  end

  def agent(text, at: Time.current)
    create(:message, conversation: conversation, account: account, message_type: 'outgoing',
                     content: text, created_at: at)
  end

  def score
    described_class.new(conversation: conversation, assistant: assistant).perform&.temperature
  end

  describe 'deterministic signals' do
    # These are true whether or not a model agrees, which is exactly why they
    # carry most of the weight.
    it 'scores an explicit price question' do
      customer('quanto custa a progressiva?')

      expect(score).to eq(described_class::ASKED_PRICE + 15)
    end

    it 'scores a request for a slot' do
      customer('tem horário na sexta?')

      expect(score).to eq(described_class::ASKED_SCHEDULE + 15)
    end

    it 'scores a checkout link that was never paid' do
      customer('quero comprar')
      agent('Segue o link: https://pay.univercart.com/abc')

      expect(score).to eq(described_class::ABANDONED_CHECKOUT + 15)
    end

    it 'does not score a checkout the customer said they paid' do
      customer('quero comprar')
      agent('Segue o link: https://pay.univercart.com/abc')
      customer('paguei agora')

      expect(score).to eq(15)
    end

    it 'scores a returning customer' do
      create(:conversation, account: account, contact: conversation.contact)
      customer('oi')

      expect(score).to eq(described_class::RETURNING_CUSTOMER + 15)
    end
  end

  describe 'decay' do
    # A hot lead that waits a week is not a hot lead. Without decay the radar
    # fills up with three-month-old enthusiasm.
    it 'cools a lead down over time' do
      customer('quanto custa?', at: 5.days.ago)

      expect(score).to eq(described_class::ASKED_PRICE + 15 - (5 * described_class::DECAY_PER_DAY))
    end

    it 'never goes below zero' do
      customer('oi', at: 400.days.ago)

      expect(score).to eq(0)
    end
  end

  describe 'the model reading' do
    it 'adds intent and urgency' do
      reader_says(intencao_compra: 15, urgencia: 10, objecao_forte: 0)
      customer('oi')

      expect(score).to eq(15 + 10 + 15)
    end

    it 'subtracts a strong objection' do
      reader_says(intencao_compra: 0, urgencia: 0, objecao_forte: -10)
      customer('oi')

      expect(score).to eq(5)
    end

    # The deterministic 60 still stand. A scoring miss must never cost the
    # opportunity record itself.
    it 'still records the lead when the model call fails' do
      allow(claude).to receive(:chat).and_raise(Ai::ClaudeService::Error, 'boom')
      customer('quanto custa?')

      expect(score).to eq(described_class::ASKED_PRICE)
    end

    it 'survives a model that answers with prose instead of JSON' do
      allow(claude).to receive(:chat).and_return({ content: 'não sei dizer', model: 'haiku' })
      customer('quanto custa?')

      expect(score).to eq(described_class::ASKED_PRICE)
    end
  end

  describe 'the record' do
    it 'stores what the score was built from' do
      customer('quanto custa?')

      opportunity = described_class.new(conversation: conversation, assistant: assistant).perform

      expect(opportunity.signals['asked_price']).to be(true)
      expect(opportunity.band).to be_a(String)
    end

    it 'never invents a value the model did not report' do
      reader_says(intencao_compra: 5, urgencia: 0, objecao_forte: 0, valor_potencial: 0)
      customer('quanto custa?')

      expect(described_class.new(conversation: conversation, assistant: assistant).perform.potential_brl)
        .to eq(0)
    end

    # Re-scoring a conversation updates the lead instead of stacking duplicates
    # in the radar.
    it 'updates the existing opportunity on a re-score' do
      customer('quanto custa?')
      described_class.new(conversation: conversation, assistant: assistant).perform

      expect { described_class.new(conversation: conversation, assistant: assistant).perform }
        .not_to(change(Ai::LeadOpportunity, :count))
    end

    it 'ignores a conversation where the customer never spoke' do
      agent('oi, tudo bem?')

      expect(described_class.new(conversation: conversation, assistant: assistant).perform).to be_nil
    end
  end
end
