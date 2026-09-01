# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::Conversations::ScanService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:scan) { create(:ai_manager_conversation_scan, account: account, window_hours: 24) }

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
    it 'registra por que a leitura por modelo não aconteceu' do
      described_class.new(scan: scan).perform

      expect(scan.reload.summary['reading_skipped']).to include('Nenhum agente')
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
end
