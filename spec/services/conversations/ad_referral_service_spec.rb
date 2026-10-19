require 'rails_helper'

RSpec.describe Conversations::AdReferralService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  let(:pt_br_content) do
    <<~TEXT
      📢 **ANÚNCIO DO FACEBOOK**
      **Título:** Progressiva com 30% off
      **Descrição:**
      Agende pelo WhatsApp e ganhe desconto
      **Link do Anúncio:** [Ver no Facebook](https://fb.me/abc123)
      **ID do Anúncio:** 120212345678901234
      ---
      💬 **MENSAGEM DO CLIENTE:**
      Oi, vi o anúncio e quero agendar
    TEXT
  end

  def inbound(content)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  describe '.ad_message?' do
    it 'recognises the WAHA Facebook ad block in Portuguese and English' do
      expect(described_class.ad_message?(pt_br_content)).to be true
      expect(described_class.ad_message?("📢 **FACEBOOK AD**\n**Title:** Promo\n**Ad ID:** 1\n---\n💬 **CUSTOMER MESSAGE:**\nhi")).to be true
    end

    it 'ignores ordinary messages' do
      expect(described_class.ad_message?('Oi, vi o anúncio de vocês')).to be false
      expect(described_class.ad_message?(nil)).to be false
    end
  end

  describe '#perform' do
    it 'stores the parsed ad on the message' do
      message = inbound(pt_br_content)

      described_class.new(message).perform

      expect(message.reload.content_attributes['ad_referral']).to include(
        'source' => 'facebook',
        'ad_id' => '120212345678901234',
        'title' => 'Progressiva com 30% off',
        'body' => 'Agende pelo WhatsApp e ganhe desconto',
        'url' => 'https://fb.me/abc123',
        'customer_message' => 'Oi, vi o anúncio e quero agendar'
      )
    end

    it 'stamps the conversation and contact on first touch and creates the attribute definitions' do
      described_class.new(inbound(pt_br_content)).perform

      attrs = conversation.reload.custom_attributes
      expect(attrs).to include('origem_lead' => 'anuncio_facebook', 'anuncio_id' => '120212345678901234',
                               'anuncio_titulo' => 'Progressiva com 30% off', 'anuncio_url' => 'https://fb.me/abc123',
                               'anuncio_cliques' => 1)
      expect(contact.reload.custom_attributes['origem_lead']).to eq('anuncio_facebook')
      expect(account.custom_attribute_definitions.where(attribute_model: 'conversation_attribute').pluck(:attribute_key))
        .to include('origem_lead', 'anuncio_id', 'anuncio_titulo', 'anuncio_url', 'anuncio_cliques')
      expect(account.custom_attribute_definitions.find_by(attribute_key: 'origem_lead', attribute_model: 'contact_attribute')).to be_present
    end

    it 'ensures the lead label exists on the account' do
      described_class.new(inbound(pt_br_content)).perform

      expect(account.labels.find_by(title: described_class::LABEL)).to be_present
    end

    it 'dispatches conversation.ad_referral once per conversation' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      described_class.new(inbound(pt_br_content)).perform

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::CONVERSATION_AD_REFERRAL, kind_of(Time),
        hash_including(conversation: conversation, ad_referral: hash_including('ad_id' => '120212345678901234'))
      ).once
    end

    it 'keeps the first ad and only counts a second click' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      described_class.new(inbound(pt_br_content)).perform
      second = inbound(pt_br_content.sub('120212345678901234', '999').sub('Progressiva com 30% off', 'Outro anúncio'))

      described_class.new(second).perform

      attrs = conversation.reload.custom_attributes
      expect(attrs['anuncio_id']).to eq('120212345678901234')
      expect(attrs['anuncio_titulo']).to eq('Progressiva com 30% off')
      expect(attrs['anuncio_cliques']).to eq(2)
      expect(second.reload.content_attributes['ad_referral']['ad_id']).to eq('999')
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_AD_REFERRAL, anything, anything).once
    end

    it 'does nothing for a message without the ad block' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      message = inbound('Oi, quero agendar')

      described_class.new(message).perform

      expect(message.reload.content_attributes['ad_referral']).to be_nil
      expect(conversation.reload.custom_attributes['anuncio_id']).to be_nil
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::CONVERSATION_AD_REFERRAL, anything, anything)
    end

    it 'ignores outgoing echoes that quote the block' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: pt_br_content)

      described_class.new(message).perform

      expect(conversation.reload.custom_attributes['anuncio_id']).to be_nil
    end
  end
end
