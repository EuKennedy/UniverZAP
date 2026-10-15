# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Broadcasts::AudienceResolver do
  let(:account) { create(:account) }

  def resolver_for(*numbers)
    broadcast = create(:broadcast, account: account, audience: { 'phone_numbers' => numbers })
    described_class.new(broadcast)
  end

  # A lista colada no composer chega crua. Comparar isso com o que esta gravado
  # em contacts sem normalizar fazia a audiencia resolver para zero, em silencio.
  describe 'normalizacao da lista de telefones' do
    {
      '31984956383' => '+5531984956383',
      '(31) 98495-6383' => '+5531984956383',
      '5531984956383' => '+5531984956383',
      '+5531984956383' => '+5531984956383',
      # Celular antigo de 8 digitos ganha o nono.
      '551199998888' => '+5511999998888'
    }.each do |entrada, esperado|
      it "resolve #{entrada.inspect} para #{esperado}" do
        expect(resolver_for(entrada).missing_phone_numbers).to eq([esperado])
      end
    end

    # O + e o contrato: quem ja carrega codigo de pais nao recebe outro. Sem
    # isto um numero dos EUA virava brasileiro.
    it 'nao prefixa 55 em numero internacional que veio com +' do
      expect(resolver_for('+12125551234').missing_phone_numbers).to eq(['+12125551234'])
    end

    # O normalizador insere o nono digito sempre que o resultado nao tem 13
    # digitos, o que transformaria um fixo no celular de outra pessoa.
    it 'nao inventa o nono digito num fixo' do
      expect(resolver_for('3133334444').missing_phone_numbers).to eq(['+553133334444'])
    end

    it 'descarta o que e curto demais para ser telefone' do
      expect(resolver_for('119999').missing_phone_numbers).to be_empty
    end
  end

  describe 'materializacao dos contatos' do
    it 'cria o contato que ainda nao existe' do
      resolver = resolver_for('31984956383')

      expect { resolver.ensure_contacts! }.to change { account.contacts.count }.by(1)
    end

    it 'passa a resolver o numero depois de materializar' do
      resolver = resolver_for('31984956383')
      resolver.ensure_contacts!

      expect(resolver.contact_ids).to eq(account.contacts.pluck(:id))
    end

    it 'nao duplica contato que ja existe, mesmo digitado sem formatacao' do
      create(:contact, account: account, phone_number: '+5531984956383')
      resolver = resolver_for('(31) 98495-6383')

      expect(resolver.missing_phone_numbers).to be_empty
      expect { resolver.ensure_contacts! }.not_to(change { account.contacts.count })
    end
  end

  # A previa so conta; quem escreve e o disparo. Criar contato ao clicar em
  # pre-visualizar encheria a base de quem so queria ver o tamanho da lista.
  describe 'a previa nao escreve no banco' do
    it 'conta o numero frio sem cria-lo' do
      resolver = resolver_for('31984956383')

      expect { resolver.contact_ids }.not_to(change { account.contacts.count })
      expect(resolver.missing_phone_numbers.length).to eq(1)
    end
  end
end
