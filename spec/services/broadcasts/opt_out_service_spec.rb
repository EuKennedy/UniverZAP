# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Broadcasts::OptOutService do
  describe '.opt_out_text?' do
    ['Não quero mais receber essas mensagens', 'por favor PARE DE MANDAR', 'me tira da lista', 'Sair', 'stop',
     'quero me descadastrar', 'não me mande mais isso'].each do |text|
      it "reconhece #{text.inspect}" do
        expect(described_class.opt_out_text?(text)).to be(true)
      end
    end

    ['Vou sair mais cedo hoje', 'cancelar', 'quero receber o orçamento', 'pode parar o carro aí', ''].each do |text|
      it "ignora #{text.inspect}" do
        expect(described_class.opt_out_text?(text)).to be(false)
      end
    end
  end

  describe '#perform' do
    let(:account) { create(:account) }
    let(:contact) { create(:contact, account: account, phone_number: '+5531900000001') }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let!(:scheduled) { create(:scheduled_message, conversation: conversation) }
    let(:broadcast) { create(:broadcast, account: account) }
    let!(:recipient) { create(:broadcast_recipient, broadcast: broadcast, contact: contact) }

    before { described_class.new(contact).perform }

    it 'marca o contato e cria o atributo' do
      expect(contact.reload.custom_attributes['opt_out_disparos']).to be(true)
      expect(account.custom_attribute_definitions.find_by(attribute_key: 'opt_out_disparos')).to be_present
    end

    it 'cancela o agendado e pula o disparo pendente' do
      expect(scheduled.reload).to have_attributes(status: 'cancelled', cancel_reason: 'opted_out')
      expect(recipient.reload).to have_attributes(status: 'skipped', skip_reason: 'opted_out')
    end
  end
end
