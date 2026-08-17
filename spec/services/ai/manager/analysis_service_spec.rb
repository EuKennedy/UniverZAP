# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::AnalysisService do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:ids) { (1..10_000).each }
  let(:service) { described_class.new(account: account) }
  let(:finding) do
    { check_key: 'loose_promise', severity: 'high', target: 'prompt_version',
      title: 'Promessa sem turno', rationale: 'Aconteceu 3 vezes.',
      evidence: { 'conversation_id' => 1, 'excerpt' => 'já te falo', 'metric' => 'porcentagem_das_respostas',
                  'value' => 15.0 },
      proposed: { 'instruction' => 'Consulte agora.' } }
  end

  # Volume suficiente para concluir, com o padrão de promessa solta dentro dele.
  def traffic(conversations:, promises: 0, agent: nil)
    agent ||= assistant
    conversations.times do |index|
      flags = index < promises ? %w[promessa_solta] : []
      id = ids.next
      create(:ai_invocation, account: agent.account, ai_assistant: agent, conversation_id: id,
                             message_id: id, ai_response: 'Deixa eu confirmar e já te falo.',
                             auto_flags: flags, auto_flag: Ai::Invocation.primary_flag(flags),
                             created_at: 2.days.ago)
    end
  end

  describe 'a rodada que conclui' do
    before { traffic(conversations: 20, promises: 3) }

    it 'grava o que analisou junto do que concluiu' do
      run = service.perform

      expect(run.status).to eq('done')
      expect(run.conversations_analysed).to eq(20)
      expect(run.summary['suggestions_created']).to eq(1)
      expect(run.period_start).to be_present
    end

    it 'não cobra crédito nenhum, porque nenhuma verificação da v1 chama modelo' do
      expect(service.perform.cost_cents_brl).to be_zero
    end

    it 'abre a sugestão pendente, esperando decisão humana' do
      service.perform
      suggestion = Ai::Manager::Suggestion.find_by(ai_assistant_id: assistant.id)

      expect(suggestion.status).to eq('pending')
      expect(suggestion.check_key).to eq('loose_promise')
    end
  end

  # Amostra pequena não vira conclusão fraca, vira recusa com o número que falta.
  describe 'a recusa por amostra pequena' do
    before { traffic(conversations: 5, promises: 4) }

    it 'recusa concluir e diz quantas conversas faltam' do
      run = service.perform

      expect(run).to be_insufficient_data
      expect(run.summary['analysed']).to eq(5)
      expect(run.summary['needed']).to eq(described_class::MIN_CONVERSATIONS)
      expect(run.summary['missing']).to eq(described_class::MIN_CONVERSATIONS - 5)
    end

    it 'termina como rodada certa, e não como falha' do
      expect(service.perform.status).to eq('done')
    end

    it 'não escreve sugestão nenhuma' do
      expect { service.perform }.not_to change(Ai::Manager::Suggestion, :count)
    end
  end

  describe 'o liga/desliga do operador' do
    before { traffic(conversations: 20, promises: 3) }

    it 'não roda a verificação que a conta desligou' do
      create(:ai_manager_check_setting, account: account, check_key: 'loose_promise', enabled: false)

      expect { service.perform }.not_to change(Ai::Manager::Suggestion, :count)
    end

    it 'roda a verificação que outra conta desligou, porque a configuração é da conta' do
      create(:ai_manager_check_setting, account: create(:account), check_key: 'loose_promise', enabled: false)

      expect { service.perform }.to change(Ai::Manager::Suggestion, :count).by(1)
    end
  end

  describe 'a deduplicação' do
    before { traffic(conversations: 20, promises: 3) }

    it 'escreve uma sugestão só quando a verificação devolve o mesmo achado duas vezes' do
      noisy = class_double(Ai::Manager::Checks::LoosePromise, key: 'loose_promise',
                                                              cost_per_conversation_cents: 0,
                                                              run: [finding, finding])
      allow(Ai::Manager::Checks).to receive(:enabled_for).and_return([noisy])

      service.perform

      expect(Ai::Manager::Suggestion.where(ai_assistant_id: assistant.id).count).to eq(1)
    end

    # Repetir toda semana o que o operador ainda não decidiu transforma a fila
    # num lugar que ninguém abre.
    it 'não repete na semana seguinte a carta que continua aberta' do
      service.perform

      expect { described_class.new(account: account).perform }.not_to change(Ai::Manager::Suggestion, :count)
    end
  end

  # Metade da auditoria vale mais que nenhuma.
  it 'entrega o resto quando uma verificação estoura' do
    traffic(conversations: 20, promises: 3)
    broken = class_double(Ai::Manager::Checks::DiedOnPrice, key: 'died_on_price', cost_per_conversation_cents: 0)
    allow(broken).to receive(:run).and_raise(StandardError, 'boom')
    allow(Ai::Manager::Checks).to receive(:enabled_for).and_return([broken, Ai::Manager::Checks::LoosePromise])

    run = service.perform

    expect(run.status).to eq('done')
    expect(Ai::Manager::Suggestion.where(check_key: 'loose_promise').count).to eq(1)
  end

  # A regra mais importante desta base, provada no motor e não só na controller:
  # a varredura de uma conta nunca enxerga o agente de outra.
  it 'nunca escreve sugestão sobre o agente de outra conta' do
    stranger = create(:ai_assistant, account: create(:account))
    traffic(conversations: 20, promises: 3)
    traffic(conversations: 20, promises: 20, agent: stranger)

    service.perform

    expect(Ai::Manager::Suggestion.where(ai_assistant_id: stranger.id)).to be_empty
    expect(Ai::Manager::Suggestion.where(account_id: stranger.account_id)).to be_empty
  end
end
