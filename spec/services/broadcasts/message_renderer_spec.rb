# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Broadcasts::MessageRenderer do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'mariana souza', custom_attributes: { 'ultima_visita' => '2026-09-12' }) }
  let(:conversation) do
    create(:conversation, account: account, contact: contact, custom_attributes: { 'servico' => 'Escova', 'profissional' => 'Ana' })
  end

  def render(text, seed: 1, variants: [])
    described_class.new(contact: contact, conversation: conversation, seed: seed).render(text, variants: variants)
  end

  it 'preenche as variáveis da cliente' do
    expect(render('Oi {primeiro_nome}! {nome}, sua {servico} com {profissional}; última visita {ultima_visita}'))
      .to eq('Oi Mariana! mariana souza, sua Escova com Ana; última visita 12/09')
  end

  it 'mantém as variáveis antigas {contact.*}' do
    expect(render('Olá {contact.name}')).to eq('Olá mariana souza')
  end

  it 'resolve o spintax de forma estável pela semente' do
    first = render('{Oi|Olá|Oie} {primeiro_nome}', seed: 7)

    expect(first).to match(/\A(Oi|Olá|Oie) Mariana\z/)
    expect(render('{Oi|Olá|Oie} {primeiro_nome}', seed: 7)).to eq(first)
  end

  it 'varia entre sementes (não manda o texto idêntico para todas)' do
    texts = (1..30).map { |seed| render('{Oi|Olá|Oie}, {tudo bem|como vai}?', seed: seed) }

    expect(texts.uniq.size).to be > 2
  end

  it 'escolhe entre as versões escritas' do
    texts = (1..30).map { |seed| render('Versão A', seed: seed, variants: ['Versão B', 'Versão C']) }

    expect(texts.uniq).to contain_exactly('Versão A', 'Versão B', 'Versão C')
  end

  it 'não chama a cliente pelo número quando o nome é um telefone' do
    contact.update!(name: '+55 31 99999-0000')

    expect(render('Oi {primeiro_nome}, tudo bem?')).to eq('Oi , tudo bem?')
  end

  it 'aponta as variáveis que ficariam vazias' do
    conversation.update!(custom_attributes: {})
    renderer = described_class.new(contact: contact, conversation: conversation, seed: 1)

    expect(renderer.missing_variables('Sua {servico} com {profissional}, {primeiro_nome}')).to contain_exactly('servico', 'profissional')
  end
end
