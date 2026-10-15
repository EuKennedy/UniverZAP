# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Broadcasts::RecipientSenderService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5531984956383') }

  # O primeiro template do factory: body com uma variavel, idioma 'id'.
  let(:template) do
    { 'name' => 'sample_shipping_confirmation', 'language' => 'id',
      'processed_params' => { 'body' => { '1' => '3' } } }
  end

  let(:broadcast) do
    create(:broadcast, account: account, inbox: inbox, mode: 'official',
                       message: { 'template' => template })
  end
  let(:recipient) { create(:broadcast_recipient, broadcast: broadcast, contact: contact) }

  # `send_template` e delegado a um provider_service NOVO a cada chamada, entao
  # stubar o objeto channel nao interceptaria nada.
  let(:provider) { instance_double(Whatsapp::Providers::WhatsappCloudService) }

  before do
    allow(Whatsapp::Providers::WhatsappCloudService).to receive(:new).and_return(provider)
  end

  def send!
    described_class.new(recipient).perform
    recipient.reload
  end

  describe 'quando a Meta aceita o template' do
    before { allow(provider).to receive(:send_template).and_return('wamid.ABC123') }

    it 'marca o destinatario como enviado' do
      expect(send!).to be_status_sent
    end

    # Sem isto o atendente abre uma conversa vazia quando o cliente responde, sem
    # saber o que foi disparado.
    it 'grava a mensagem na timeline' do
      send!

      expect(inbox.messages.outgoing.count).to eq(1)
    end

    # `Base::SendOnChannelService` pula qualquer mensagem que carregue source_id.
    # E o que impede o template de sair uma segunda vez pelo caminho normal.
    it 'guarda o id do provedor na mensagem, para nao reenviar' do
      send!

      expect(inbox.messages.outgoing.last.source_id).to eq('wamid.ABC123')
    end

    it 'liga o destinatario a conversa criada' do
      send!

      expect(recipient.conversation_id).to be_present
    end
  end

  describe 'quando a Meta recusa' do
    # `send_template` devolve nil em qualquer recusa — template pausado, numero
    # fora do WhatsApp, limite de tier. Confiar na chamada em vez da resposta
    # fazia um disparo inteiro reportar 100% enviado com zero entregue.
    before { allow(provider).to receive(:send_template).and_return(nil) }

    it 'marca o destinatario como falho' do
      expect(send!).to be_status_failed
    end

    it 'nao inventa uma conversa para uma mensagem que nao saiu' do
      send!

      expect(inbox.messages.outgoing.count).to eq(0)
    end
  end

  describe 'quando o template nao esta aprovado nesta caixa' do
    let(:template) do
      { 'name' => 'template_que_nao_existe', 'language' => 'id', 'processed_params' => {} }
    end

    # O TemplateProcessorService devolve o nome pedido aconteca o que acontecer,
    # entao o nome nao prova nada. Quem prova a existencia e `parameters`.
    it 'falha antes de chamar o provedor' do
      allow(provider).to receive(:send_template)

      send!

      expect(provider).not_to have_received(:send_template)
      expect(recipient).to be_status_failed
    end
  end

  describe 'quando a mensagem sai mas a timeline quebra' do
    before do
      allow(provider).to receive(:send_template).and_return('wamid.XYZ')
      allow(Message).to receive(:create!).and_raise(StandardError, 'banco fora do ar')
    end

    # A partir do id do provedor o envio e fato consumado. Reescrever isso como
    # `failed` manda o operador reenviar para quem ja recebeu.
    it 'mantem o destinatario como enviado' do
      expect(send!).to be_status_sent
    end
  end

  describe 'quando o contato nao tem telefone' do
    let(:contact) { create(:contact, account: account, phone_number: nil) }

    it 'falha sem chamar o provedor' do
      allow(provider).to receive(:send_template)

      send!

      expect(provider).not_to have_received(:send_template)
      expect(recipient).to be_status_failed
    end
  end
end
