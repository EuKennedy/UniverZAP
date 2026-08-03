# frozen_string_literal: true

require 'rails_helper'

# The acceptance rule the whole module rests on: no reply reaches a customer
# without a log row that can explain it. These specs drive the REAL
# Ai::ClaudeService (only the HTTP call is stubbed) because a log written by a
# test double would prove nothing about production.
RSpec.describe Ai::Invocation, 'as the agent response log' do
  let(:account) { create(:account) }
  let(:assistant) do
    create(:ai_assistant, account: account, encrypted_anthropic_key: 'sk-test', tone: 'sales')
  end
  let(:conversation) { create(:conversation, account: account) }
  let(:summarizer) { instance_double(Ai::SummarizeService, perform: { content: 'memo' }) }

  def claude_says(text)
    body = {
      'content' => [{ 'type' => 'text', 'text' => text }],
      'model' => 'claude-sonnet-4-5',
      'stop_reason' => 'end_turn',
      'usage' => { 'input_tokens' => 120, 'output_tokens' => 40 }
    }
    allow(HTTParty).to receive(:post).and_return(
      instance_double(HTTParty::Response, success?: true, code: 200, parsed_response: body)
    )
  end

  before do
    allow(Ai::SummarizeService).to receive(:new).and_return(summarizer)
    # The quota gate is not what these specs are about; without a balance the
    # first call would burn the one-shot grace credit and the second would 402.
    account.update!(token_credit_balance_cents_brl: 100_000)
    create(:ai_training, ai_assistant: assistant, title: 'Tabela de preços',
                         content: 'Progressiva sem formol R$ 189,90', status: 'ready')
    create(:message, conversation: conversation, account: account, message_type: 'incoming',
                     content: 'quanto custa a progressiva?')
  end

  def run_autopilot
    Ai::AutopilotReplyService.new(
      conversation: conversation, assistant: assistant,
      trigger_message: conversation.messages.last
    ).perform
  end

  describe 'what gets written' do
    before { claude_says(%(Fica R$ 189,90.\n<meta>{"confidence":0.93}</meta>)) }

    it 'snapshots the exact system prompt that produced the reply' do
      run_autopilot

      expect(Ai::Invocation.last.system_prompt).to include('Tabela de preços')
    end

    it 'records which knowledge passages were selected and how they ranked' do
      run_autopilot

      chunks = Ai::Invocation.last.chunks_used
      expect(chunks.first).to include('title' => 'Tabela de preços')
      expect(chunks.first['score']).to be_a(Numeric)
    end

    it 'records the question being answered' do
      run_autopilot

      expect(Ai::Invocation.last.user_message).to eq('quanto custa a progressiva?')
    end

    it 'records the delivered text without the internal meta block' do
      run_autopilot

      logged = Ai::Invocation.last.ai_response
      expect(logged).to eq('Fica R$ 189,90.')
      expect(logged).not_to include('meta')
    end

    it 'never lets the meta block reach the customer' do
      expect(run_autopilot[:content]).to eq('Fica R$ 189,90.')
    end

    it 'stores the self-assessment as a number the queue can sort on' do
      run_autopilot

      expect(Ai::Invocation.last.confidence).to eq(0.93)
    end

    it 'stores what the operator was actually charged, in BRL' do
      run_autopilot

      expect(Ai::Invocation.last.cost_brl).to be > 0
    end

    # The golden rule: the row exists before anything can be sent.
    it 'opens the row as pending, so an undelivered reply stays visible' do
      run_autopilot

      expect(Ai::Invocation.last.delivery_status).to eq('pending')
    end

    # Without this the job has to guess which calls belong to which turn, and a
    # 5-minute window guesses wrong the moment two turns overlap.
    it 'stamps the customer message the turn is answering' do
      run_autopilot

      expect(Ai::Invocation.last.trigger_message_id).to eq(conversation.messages.first.id)
    end
  end

  describe 'guardrail flags' do
    it 'flags a low self-assessment' do
      claude_says(%(Acho que fica R$ 189,90.\n<meta>{"confidence":0.2}</meta>))

      run_autopilot

      expect(Ai::Invocation.last.auto_flag).to eq('baixa_confianca')
    end

    # The reply is suppressed, so nothing is delivered. The attempt still has to
    # be in the log, which is the whole point of writing before sending.
    it 'flags and records a price the operator never set, even when suppressed' do
      claude_says('Fica R$ 999,00.')

      expect { run_autopilot }.to raise_error(Ai::AutopilotReplyService::UngroundedClaim)

      logged = Ai::Invocation.order(:id).last
      expect(logged.auto_flag).to eq('preco_inventado')
      expect(logged.ai_response).to eq('Fica R$ 999,00.')
      expect(logged.delivery_status).to eq('pending')
    end
  end

  describe 'phases that do not face a customer' do
    it 'leaves the reply columns empty on a summary call' do
      claude_says('resumo')

      Ai::ClaudeService.new(assistant: assistant, account: account)
                       .chat(messages: [{ role: 'user', content: 'oi' }], system: 'x', phase: 'summary')

      invocation = Ai::Invocation.last
      expect(invocation.delivery_status).to be_nil
      expect(invocation.system_prompt).to be_nil
    end
  end
end
