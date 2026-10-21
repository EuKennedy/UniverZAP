require 'rails_helper'

RSpec.describe Chatflow::AnswerCapture do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:chatflow) { Chatflow.create!(account: account, name: 'Cadastro') }

  def capture(field_type, save_to = {})
    node = flow_node(chatflow, :question, { 'field_type' => field_type, 'save_to' => save_to })
    described_class.new(node, conversation)
  end

  describe '#parse' do
    it 'nome tira o "meu nome é" e recusa só números' do
      expect(capture('name').parse('meu nome é Ana Lima')).to eq('Ana Lima')
      expect(capture('name').parse('12345')).to be_nil
    end

    it 'e-mail extrai do meio da frase e normaliza' do
      expect(capture('email').parse('é Ana.Lima@Gmail.com.')).to eq('ana.lima@gmail.com')
      expect(capture('email').parse('não tenho')).to be_nil
    end

    it 'telefone aceita com e sem 55 e recusa curto' do
      expect(capture('phone').parse('(11) 98888-7777')).to eq('+5511988887777')
      expect(capture('phone').parse('+55 11 98888-7777')).to eq('+5511988887777')
      expect(capture('phone').parse('9888')).to be_nil
    end

    it 'data aceita dd/mm, dd/mm/aa e ISO; recusa data impossível' do
      travel_to(Time.zone.local(2026, 10, 21)) do
        expect(capture('date').parse('25/10')).to eq('2026-10-25')
        expect(capture('date').parse('dia 5/3/90')).to eq('1990-03-05')
        expect(capture('date').parse('10/01/27')).to eq('2027-01-10')
        expect(capture('date').parse('1990-05-20')).to eq('1990-05-20')
        expect(capture('date').parse('31/02/2026')).to be_nil
      end
    end

    it 'número entende vírgula decimal e milhar com ponto' do
      expect(capture('number').parse('R$ 1.234,56')).to eq(1234.56)
      expect(capture('number').parse('pedido 10234')).to eq(10_234)
      expect(capture('number').parse('sei não')).to be_nil
    end

    it 'texto livre só recusa vazio' do
      expect(capture('text').parse('  corte e escova ')).to eq('corte e escova')
      expect(capture('text').parse('   ')).to be_nil
    end
  end

  describe '#save' do
    it 'grava campo do contato, atributo do contato e atributo da conversa' do
      capture('email', 'scope' => 'contact', 'key' => 'email').save('ana@gmail.com')
      capture('date', 'scope' => 'contact', 'key' => 'data_nascimento').save('1990-05-20')
      capture('text', 'scope' => 'conversation', 'key' => 'servico').save('escova')

      expect(conversation.contact.reload.email).to eq('ana@gmail.com')
      expect(conversation.contact.custom_attributes['data_nascimento']).to eq('1990-05-20')
      expect(conversation.reload.custom_attributes['servico']).to eq('escova')
    end

    it 'e-mail de outro contato não derruba o fluxo' do
      create(:contact, account: account, email: 'ana@gmail.com')

      expect(capture('email', 'scope' => 'contact', 'key' => 'email').save('ana@gmail.com')).to eq('email')
    end
  end
end
