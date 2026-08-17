# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Belezaki::CustomerPhone do
  let(:conversation) { create(:conversation) }

  def heard(text)
    create(:message, conversation: conversation, account: conversation.account,
                     inbox: conversation.inbox, message_type: :incoming, content: text)
  end

  def phone(fallback: nil)
    described_class.new(conversation: conversation, fallback: fallback)
  end

  describe 'de onde sai o numero' do
    it 'le a ficha do contato' do
      conversation.contact.update!(phone_number: '+5531987654321')

      expect(phone.value).to eq('+5531987654321')
    end

    # Sem conversa não há ficha para ler, e é assim que o playground e os
    # diagnósticos rodam. O fallback existe para eles, nunca para o modelo.
    it 'aceita o numero informado por quem construiu, quando nao ha ficha' do
      semi = described_class.new(conversation: nil, fallback: '+5531987654321')

      expect(semi.value).to eq('+5531987654321')
    end

    it 'fica vazio quando o contato nao tem telefone' do
      expect(phone).not_to be_present
    end
  end

  describe 'registrar o numero que o cliente digitou' do
    it 'aceita o numero em qualquer pontuacao' do
      heard('meu zap é (31) 98765-4321 viu')

      expect(phone.register('(31) 98765-4321')).to eq([:ok, '+5531987654321'])
    end

    it 'aceita quando o cliente ja escreveu com o codigo do pais' do
      heard('anota ai +55 31 98765 4321')

      expect(phone.register('+5531987654321').first).to eq(:ok)
    end

    # A trava principal. Numa conversa real o modelo preencheu este campo com
    # três números inventados diferentes, e cada um virou um agendamento órfão.
    it 'recusa um numero que o cliente nunca disse' do
      heard('oi, quero marcar uma unha')

      status, motivo = phone.register('+5511999999999')

      expect(status).to eq(:recusado)
      expect(motivo).to include('Não vi esse número')
    end

    # O que o modelo inventou de verdade. Nenhum DDD brasileiro tem zero.
    it 'recusa DDD inexistente' do
      heard('+5500000000000')

      expect(phone.register('+5500000000000').first).to eq(:recusado)
    end

    # O destino é o WhatsApp: um fixo aceita a reserva e nunca recebe a
    # confirmação, que é a pior combinação possível.
    it 'recusa telefone fixo' do
      heard('pode ligar no 31 3333-4444')

      expect(phone.register('3133334444').first).to eq(:recusado)
    end

    it 'grava na ficha, e o proximo agendamento ja enxerga' do
      heard('31 98765-4321')

      phone.register('31 98765-4321')

      expect(conversation.reload.contact.phone_number).to eq('+5531987654321')
    end

    # Uma falha ao gravar o contato não pode custar a resposta que o cliente
    # está esperando do outro lado.
    it 'devolve recusa em vez de estourar quando a ficha nao aceita' do
      heard('31 98765-4321')
      allow(conversation.contact).to receive(:update!).and_raise(StandardError, 'banco fora')

      expect(phone.register('31 98765-4321').first).to eq(:recusado)
    end
  end
end
