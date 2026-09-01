# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::Conversations::Listing do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def finding(case_key: 'cliente_esperando', severity: 'high', occurred_ago: 2.hours, **extra)
    target = extra[:on] || account
    author = extra.fetch(:author, 'none')
    value_cents = extra.fetch(:value_cents, 0)
    conversation = extra[:conversation] || create(:conversation, account: target, inbox: inbox_for(target))
    Ai::Manager::ConversationFinding.create!(
      account: target, conversation_id: conversation.id, conversation_display_id: conversation.display_id,
      contact_id: conversation.contact_id, case_key: case_key, severity: severity, author: author,
      title: 'Cliente esperando resposta', detail: 'Alguém está esperando.', source: 'triage',
      value_cents_brl: value_cents, occurred_at: occurred_ago.ago, last_seen_at: Time.current
    )
  end

  def inbox_for(target)
    target == account ? inbox : create(:inbox, account: target)
  end

  def keys(**)
    described_class.new(account: account, **).payload[:findings].pluck(:case_key)
  end

  describe 'o filtro de dias' do
    # A promessa da tela: a leitura fica GRAVADA e o filtro fatia o que já
    # existe. Nada aqui pode disparar leitura nova nem custar um token.
    before do
      finding(case_key: 'cliente_esperando', occurred_ago: 2.hours)
      finding(case_key: 'compra_travada', occurred_ago: 5.days)
      finding(case_key: 'agente_repetiu', occurred_ago: 20.days)
    end

    it 'mostra só o que aconteceu nas últimas 24 horas' do
      expect(keys(days: 1)).to eq(['cliente_esperando'])
    end

    it 'alarga sem reanalisar nada quando o operador pede sete dias' do
      expect(keys(days: 7)).to contain_exactly('cliente_esperando', 'compra_travada')
    end

    it 'mostra tudo que está gravado quando nenhuma janela é pedida' do
      expect(keys.length).to eq(3)
    end

    # Um valor fora da lista não pode virar um filtro silencioso: a tela pediu
    # "tudo" com um número que não existe, e esconder linhas por causa disso
    # faria o operador concluir que não há nada quando há.
    it 'ignora janela desconhecida em vez de inventar um corte' do
      expect(keys(days: 999).length).to eq(3)
    end
  end

  describe 'o filtro de autor' do
    before do
      finding(case_key: 'cliente_esperando', author: 'agent')
      finding(case_key: 'compra_travada', author: 'human')
      finding(case_key: 'agente_repetiu', author: 'none')
    end

    it 'mostra só o que o agente atendeu' do
      expect(keys(author: 'agent')).to eq(['cliente_esperando'])
    end

    it 'mostra só o que a equipe atendeu' do
      expect(keys(author: 'human')).to eq(['compra_travada'])
    end

    it 'ignora autor desconhecido em vez de esvaziar a lista' do
      expect(keys(author: 'ninguem').length).to eq(3)
    end
  end

  describe 'a ordem' do
    it 'põe o mais grave na frente' do
      finding(case_key: 'agente_repetiu', severity: 'medium')
      finding(case_key: 'compra_travada', severity: 'critical')

      expect(keys.first).to eq('compra_travada')
    end

    # Dentro da mesma gravidade, dinheiro parado decide. Cliente de R$ 900 vem
    # antes de dúvida de R$ 40, mesmo sendo mais recente.
    it 'desempata pelo dinheiro parado' do
      finding(case_key: 'agente_repetiu', severity: 'high', value_cents: 4_000)
      finding(case_key: 'compra_travada', severity: 'high', value_cents: 90_000)

      expect(keys.first).to eq('compra_travada')
    end

    # O contrário de uma lista de notícias, de propósito: a linha mais velha é a
    # pessoa que está esperando há mais tempo, e empurrá-la para o fim é o mesmo
    # que perdê-la de novo.
    it 'dentro do empate, quem espera há mais tempo vem primeiro' do
      finding(case_key: 'agente_repetiu', occurred_ago: 2.hours)
      finding(case_key: 'compra_travada', occurred_ago: 20.hours)

      expect(keys.first).to eq('compra_travada')
    end
  end

  describe 'o achado que já foi resolvido' do
    # Um achado de terça dizendo "esperando há 30h" continua no banco depois que
    # alguém respondeu na quarta. Mostrá-lo igual manda o operador atender de
    # novo quem já foi atendido; apagá-lo destruiria o histórico que ele pediu
    # para ficar gravado. A saída é marcar e empurrar para o fim.
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    before do
      finding(case_key: 'cliente_esperando', conversation: conversation, occurred_ago: 30.hours)
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, content: 'Desculpa a demora!', created_at: 2.hours.ago)
    end

    it 'marca como respondida depois em vez de sumir com ela' do
      card = described_class.new(account: account).payload[:findings].first

      expect(card[:answered_after]).to be(true)
    end

    it 'empurra a resolvida para baixo da que ainda espera' do
      finding(case_key: 'compra_travada', severity: 'high', occurred_ago: 1.hour)

      expect(keys.last).to eq('cliente_esperando')
    end
  end

  describe 'as contagens' do
    # Contadas sobre o conjunto FILTRADO e não sobre a página: o operador precisa
    # saber que existem críticos mesmo quando o teto cortou a lista.
    it 'conta por gravidade e por autor sobre o filtro inteiro' do
      finding(case_key: 'cliente_esperando', severity: 'critical', author: 'agent')
      finding(case_key: 'compra_travada', severity: 'critical', author: 'human')
      finding(case_key: 'agente_repetiu', severity: 'medium', author: 'agent')

      counts = described_class.new(account: account).payload[:counts]

      expect(counts[:total]).to eq(3)
      expect(counts[:by_severity]).to eq('critical' => 2, 'medium' => 1)
      expect(counts[:by_author]).to eq('agent' => 2, 'human' => 1)
    end
  end

  # A regra mais importante desta base.
  it 'nunca mostra achado de outra conta' do
    finding(on: create(:account))

    expect(described_class.new(account: account).payload[:findings]).to be_empty
  end
end
