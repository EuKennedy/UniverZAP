require 'rails_helper'

RSpec.describe Ai::Wiki::Manual do
  subject(:sections) { described_class.sections }

  it 'lê as seções da mesma página que /docs serve' do
    expect(sections.map(&:slug)).to include('whatsapp', 'campanhas', 'kanban')
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

  # Cada seção precisa caber num chunk do Ai::KnowledgeGrounding (700 chars),
  # senão ela é partida no meio e o ranking passa a escolher metade de resposta.
  it 'mantém cada seção dentro de um chunk da recuperação' do
    expect(sections.map { |s| s.body.length }.max).to be <= 700
  end
end
