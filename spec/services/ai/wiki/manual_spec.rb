require 'rails_helper'

RSpec.describe Ai::Wiki::Manual do
  subject(:sections) { described_class.sections }

  it 'lê as seções da mesma página que /docs serve' do
    expect(sections.map(&:slug)).to include('whatsapp', 'campanhas', 'kanban')
  end

  # O pedido que originou isto: o dono perguntou como conectar o WAHA e recebeu a
  # tabela comparativa, porque era só isso que existia escrito. A recuperação
  # estava certa; faltava a resposta.
  it 'traz o procedimento de conectar o WAHA, e não só a comparação' do
    waha = sections.find { |section| section.slug == 'whatsapp-waha' }

    expect(waha.body).to include('API Não Oficial').and include('Nome da sessão').and include('QR code')
  end

  it 'traz o título que está no h2' do
    expect(sections.find { |s| s.slug == 'whatsapp' }.title).to eq('WhatsApp')
  end

  # O corpo vai inteiro para o prompt. HTML ali dentro é orçamento de recuperação
  # gasto com marcação em vez de com texto que responde.
  it 'entrega texto, não marcação' do
    expect(sections.map(&:body).join).not_to match(/<[a-z]/i)
  end

  it 'não repete o título dentro do corpo' do
    intro = sections.find { |s| s.slug == 'introducao' }

    expect(intro.body).not_to start_with(intro.title)
  end

  # Changelog e cartão de contato não ensinam ninguém a usar o produto, e
  # roubariam vaga de uma seção que responde.
  it 'deixa de fora o changelog e o suporte' do
    expect(sections.map(&:slug)).not_to include('versoes', 'suporte')
  end

  # O manual INTEIRO viaja em toda pergunta do Guia, no bloco cacheado — não há
  # mais recuperação escolhendo pedaços, então o teto que importa é o do
  # conjunto, e não o de cada seção. Sem ele, alguém cola um tratado no /docs e
  # toda pergunta sobre o Chatflow passa a carregar isso junto.
  #
  # Ai::KnowledgeGrounding::KNOWLEDGE_BUDGET_CHARS é a régua de referência: o
  # dobro dela ainda é barato num prefixo que o cache cobre.
  let(:manual_budget_chars) { 12_000 }

  it 'mantém o manual inteiro dentro do orçamento' do
    expect(sections.sum { |section| section.body.length }).to be <= manual_budget_chars
  end

  # Uma seção sozinha maior que o manual inteiro de antes é sinal de que alguém
  # colou a coisa errada, não de que a documentação melhorou.
  it 'não deixa uma seção sozinha dominar o manual' do
    expect(sections.map { |section| section.body.length }.max).to be <= 2_000
  end
end
