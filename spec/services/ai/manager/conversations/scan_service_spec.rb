# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::Conversations::ScanService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  # A janela padrão, que é de sete dias: com 24h a varredura não alcança a
  # mensagem de quem está esperando há 30, e o teste passaria a medir o vazio.
  let(:scan) { create(:ai_manager_conversation_scan, account: account, window_hours: 168) }

  # Sem agente com chave, a leitura por modelo é pulada e sobra a triagem, que é
  # de graça. É o caminho padrão destes testes: o que se mede aqui é a gravação,
  # e não a conversa com a Anthropic.
  def waiting_conversation(hours: 30, name: 'Fernanda')
    contact = create(:contact, account: account, name: name)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :incoming, content: 'Consigo horário sábado?', created_at: hours.hours.ago)
    conversation
  end

  def findings
    Ai::Manager::ConversationFinding.where(account_id: account.id)
  end

  describe 'a varredura' do
    before { waiting_conversation }

    it 'grava o achado da triagem e fecha a rodada' do
      described_class.new(scan: scan).perform

      expect(scan.reload.status).to eq('done')
      expect(findings.pluck(:case_key)).to eq(['cliente_esperando'])
    end

    it 'não cobra nada quando só a triagem rodou, porque triagem é consulta' do
      described_class.new(scan: scan).perform

      expect(scan.reload.cost_cents_brl).to be_zero
    end

    # Sem isto, doze cartões parecem a operação inteira quando podem ser o teto
    # de leitura tendo cortado noventa conversas que ninguém olhou.
    #
    # A conta nasce com um agente semeado ("Sofia"), então o motivo aqui nunca é
    # a ausência de agente: é a chave de API que ninguém configurou ainda.
    it 'registra por que a leitura por modelo não aconteceu' do
      described_class.new(scan: scan).perform

      expect(scan.reload.summary['reading_skipped']).to include('sem chave de API')
    end
  end

  describe 'rodar de novo' do
    # A promessa da tela: a leitura fica gravada e os filtros fatiam o que já
    # existe. Se a segunda rodada empilhasse cópias, o mesmo cliente apareceria
    # três vezes e o filtro por dia passaria a contar duplicata.
    it 'atualiza o mesmo achado em vez de empilhar uma cópia' do
      waiting_conversation
      described_class.new(scan: scan).perform
      described_class.new(scan: create(:ai_manager_conversation_scan, account: account)).perform

      expect(findings.count).to eq(1)
    end

    it 'aponta o achado para a varredura mais recente, para o cartão poder dizer quando foi conferido' do
      waiting_conversation
      described_class.new(scan: scan).perform
      segunda = create(:ai_manager_conversation_scan, account: account)
      described_class.new(scan: segunda).perform

      expect(findings.first.scan_id).to eq(segunda.id)
    end

    it 'recalcula a gravidade, porque o mesmo silêncio piora com o relógio' do
      waiting_conversation(hours: 7)
      described_class.new(scan: scan).perform
      expect(findings.first.severity).to eq('medium')

      # A mesma conversa, um dia depois. Janela de 30 dias para ela continuar
      # dentro do período, e o relógio adiantado para a espera passar de 7h para
      # 31h sem precisar mexer no banco por baixo do modelo.
      later = create(:ai_manager_conversation_scan, account: account, window_hours: 720)
      # 24h à frente para a espera passar de 7h para 31h sem mexer no banco.
      described_class.new(scan: later, now: 24.hours.from_now).perform

      expect(findings.first.reload.severity).to eq('critical')
    end
  end

  describe 'a limpeza' do
    it 'apaga achado mais velho que a retenção, que nenhum filtro da tela alcança' do
      old = create(:conversation, account: account, inbox: inbox)
      Ai::Manager::ConversationFinding.create!(
        account: account, conversation_id: old.id, case_key: 'cliente_esperando', severity: 'high',
        title: 'Antigo', author: 'none', source: 'triage', occurred_at: 120.days.ago, last_seen_at: 120.days.ago
      )

      described_class.new(scan: scan).perform

      expect(findings.count).to be_zero
    end
  end

  describe 'quando algo estoura' do
    before do
      allow(Ai::Manager::Conversations::Triage).to receive(:new).and_raise(StandardError, 'banco caiu')
    end

    # A tela precisa mostrar o botão de rodar de novo com o motivo do lado, e
    # não uma varredura eternamente "rodando" que ninguém sabe se acabou.
    it 'marca a varredura como falha com o motivo em vez de deixá-la pendurada' do
      described_class.new(scan: scan).perform

      expect(scan.reload.status).to eq('failed')
      expect(scan.summary['error']).to include('banco caiu')
    end
  end

  describe 'quando a triagem e a leitura acham o mesmo caso na mesma conversa' do
    # 'cliente_insatisfeito' é o único caso que os DOIS produtores emitem: a
    # triagem quando o guardrail levantou a bandeira, a leitura quando o modelo
    # enxerga a reclamação. Duas linhas com a mesma chave única dentro do MESMO
    # upsert_all fazem o Postgres recusar o comando inteiro ("ON CONFLICT DO
    # UPDATE command cannot affect row a second time"). Sendo uma sentença só,
    # nada era gravado: nem triagem, nem leitura, e a varredura morria depois de
    # o modelo já ter sido pago.
    let(:assistant) { create(:ai_assistant, account: account) }
    let(:conversation) { waiting_conversation(name: 'Marta') }
    let(:lido) do
      {
        conversation_id: conversation.id, conversation_display_id: conversation.display_id,
        contact_id: conversation.contact_id, ai_assistant_id: assistant.id,
        case_key: 'cliente_insatisfeito', severity: 'high',
        title: 'Cliente demonstrou insatisfação',
        detail: 'A Marta cobrou o retorno duas vezes e ninguém respondeu.',
        excerpt: 'esqueceram de mim?', author: 'none', source: 'reading',
        value_cents_brl: 0, occurred_at: 2.hours.ago, metadata: {}
      }
    end
    let(:reader) do
      instance_double(
        Ai::Manager::Conversations::Reader,
        findings: [lido], read_count: 1, cost_cents_brl: 12, candidate_count: 1,
        skipped_reason: nil, failures: 0, failure_reason: nil
      )
    end

    before do
      create(:ai_invocation, account: account, ai_assistant: assistant,
                             conversation_id: conversation.id, message_id: 4242,
                             ai_response: 'Sinto muito pelo ocorrido.',
                             auto_flags: %w[cliente_insatisfeito], auto_flag: 'cliente_insatisfeito',
                             created_at: 3.hours.ago)
      allow(Ai::Manager::Conversations::Reader).to receive(:new).and_return(reader)
    end

    it 'termina bem em vez de derrubar a varredura inteira' do
      described_class.new(scan: scan).perform

      expect(scan.reload.status).to eq('done')
    end

    it 'grava um cartão só para o caso repetido' do
      described_class.new(scan: scan).perform

      expect(findings.where(case_key: 'cliente_insatisfeito').count).to eq(1)
    end

    # A da leitura ganha: ela traz motivo escrito sobre AQUELA conversa, e a da
    # triagem traz uma frase de catálogo.
    it 'guarda o achado da leitura, e não o da triagem' do
      described_class.new(scan: scan).perform

      card = findings.find_by(case_key: 'cliente_insatisfeito')
      expect(card.source).to eq('reading')
      expect(card.detail).to include('cobrou o retorno')
    end

    it 'não perde os outros achados da triagem no caminho' do
      described_class.new(scan: scan).perform

      expect(findings.pluck(:case_key)).to include('cliente_esperando')
    end

    it 'grava o custo da leitura que já foi paga' do
      described_class.new(scan: scan).perform

      expect(scan.reload.cost_cents_brl).to eq(12)
    end
  end
end
