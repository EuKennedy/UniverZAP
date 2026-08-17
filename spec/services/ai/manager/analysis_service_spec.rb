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

  # O furo visto em produção, na conta de um salão: o único agente ATIVO não
  # tinha inbox nenhuma e portanto zero conversa, enquanto os dois que atendiam
  # de verdade estavam desligados. A varredura pulava os dois, não olhava uma
  # linha, e gravava um resumo dizendo que analisou tudo e não achou nada.
  describe 'quem é auditado' do
    let(:idle) { create(:ai_assistant, account: account, active: true) }
    let(:worker) { create(:ai_assistant, account: account, active: false) }

    before do
      idle
      traffic(conversations: 20, promises: 3, agent: worker)
    end

    # A instrução de um agente desligado ontem continua escrita e volta ao ar no
    # dia em que o operador religar. A lição dele é válida.
    it 'audita o agente desligado que atendeu de verdade' do
      service.perform

      expect(Ai::Manager::Suggestion.where(ai_assistant_id: worker.id).count).to eq(1)
    end

    it 'não audita o agente ligado que nunca falou' do
      service.perform

      expect(Ai::Manager::Suggestion.where(ai_assistant_id: idle.id)).to be_empty
    end

    # A régua de amostra e a varredura têm que olhar o mesmo conjunto. Medir a
    # conta inteira e varrer um subconjunto é o que fazia o resumo afirmar
    # "analisei 36 conversas" sobre agentes que tiveram zero.
    it 'mede a amostra no mesmo conjunto que varreu' do
      summary = service.perform.summary

      expect(summary['analysed']).to eq(20)
      expect(summary['agents'].map { |row| row['id'] }).to eq([worker.id])
      expect(summary['agents'].sum { |row| row['conversations'] }).to eq(summary['analysed'])
    end

    # Conta nova, ninguém atendeu ainda: a rodada ainda precisa dizer quantas
    # conversas faltam em vez de não dizer nada.
    it 'cai para os ativos quando ninguém trabalhou na janela' do
      empty = create(:account)
      active = create(:ai_assistant, account: empty, active: true)

      summary = described_class.new(account: empty).perform.summary

      expect(summary['insufficient_data']).to be(true)
      expect(summary['agents'].map { |row| row['id'] }).to eq([active.id])
    end
  end

  # "Zero sugestões porque não havia o que analisar" e "zero sugestões porque
  # está tudo bem" são coisas opostas e escreviam exatamente o mesmo texto.
  describe 'o resumo que não pode mentir' do
    it 'mostra o material que cada agente trouxe quando não achou problema' do
      traffic(conversations: 20)

      summary = service.perform.summary

      expect(summary['insufficient_data']).to be(false)
      expect(summary['suggestions_created']).to eq(0)
      expect(summary['agents']).to eq(
        [{ 'id' => assistant.id, 'name' => assistant.name, 'conversations' => 20, 'suggestions' => 0 }]
      )
    end

    it 'mostra de quem era o material quando recusa por amostra pequena' do
      traffic(conversations: 5, promises: 4)

      summary = service.perform.summary

      expect(summary['insufficient_data']).to be(true)
      expect(summary['agents'].first).to include('conversations' => 5, 'suggestions' => 0)
    end

    it 'conta as sugestões por agente, e não só o total' do
      traffic(conversations: 20, promises: 3)

      summary = service.perform.summary

      expect(summary['agents'].first).to include('conversations' => 20, 'suggestions' => 1)
      expect(summary['suggestions_created']).to eq(1)
    end
  end

  # O botão "abrir conversa" é o que sustenta o cartão: sem conferir a conversa,
  # aprovar é confiar no parecer de um robô sobre o trabalho de outro robô. A URL
  # do Chatwoot usa `display_id`, a sequência POR CONTA, e a evidência carregava
  # só a chave primária, então o botão abria a conversa de OUTRO cliente.
  it 'grava na evidência o número que a URL da conversa usa, e não a chave primária' do
    # Duas conversas de outra conta primeiro, para que chave primária e
    # display_id não possam coincidir por acidente e o teste virar decorativo.
    create_list(:conversation, 2, account: create(:account))
    conversation = create(:conversation, account: account)
    traffic(conversations: 20, promises: 3)
    # A mais recente das marcadas, que é a que a verificação cita como evidência.
    create(:ai_invocation, account: account, ai_assistant: assistant, conversation_id: conversation.id,
                           message_id: ids.next, ai_response: 'Prontinho, já deixei agendado pra você!',
                           auto_flags: %w[promessa_solta], auto_flag: 'promessa_solta', created_at: 1.hour.ago)

    service.perform
    evidence = Ai::Manager::Suggestion.find_by(check_key: 'loose_promise').evidence

    expect(conversation.display_id).not_to eq(conversation.id)
    expect(evidence['conversation_id']).to eq(conversation.id)
    expect(evidence['conversation_display_id']).to eq(conversation.display_id)
  end

  # Conversa apagada depois da rodada. O cartão esconde o botão, porque um link
  # quebrado na evidência custa mais que evidência sem link.
  it 'deixa o display_id nulo quando a conversa não existe mais' do
    traffic(conversations: 20, promises: 3)

    service.perform
    evidence = Ai::Manager::Suggestion.find_by(check_key: 'loose_promise').evidence

    expect(evidence['conversation_display_id']).to be_nil
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
