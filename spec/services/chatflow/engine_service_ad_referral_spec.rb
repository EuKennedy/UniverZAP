require 'rails_helper'

RSpec.describe Chatflow::EngineService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:chatflow) { Chatflow.create!(account: account, name: 'Lead de anúncio', inbox: inbox, status: :active, trigger_type: :ad_referral) }
  let!(:greeting) do
    ChatflowNode.create!(chatflow: chatflow, account: account, kind: :send_message, config: { 'text' => 'Vi que você veio do anúncio!' })
  end

  let(:ad_content) do
    "📢 **ANÚNCIO DO FACEBOOK**\n**Título:** Promo\n**Link do Anúncio:** [Ver no Facebook](https://fb.me/x)\n" \
      "**ID do Anúncio:** 42\n---\n💬 **MENSAGEM DO CLIENTE:**\nquero agendar"
  end

  def inbound(content, content_attributes = {})
    create(:message, conversation: conversation, account: account, message_type: 'incoming',
                     content: content, content_attributes: content_attributes)
  end

  before { chatflow.update!(start_node: greeting) }

  it 'starts the flow on a message that carries the parsed ad' do
    described_class.new(inbound('qualquer', { 'ad_referral' => { 'ad_id' => '42' } })).perform

    expect(conversation.messages.outgoing.pluck(:content)).to eq(['Vi que você veio do anúncio!'])
  end

  it 'starts the flow on the raw ad block even before the parser ran' do
    described_class.new(inbound(ad_content)).perform

    expect(ChatflowExecution.where(chatflow: chatflow).count).to eq(1)
  end

  it 'stays quiet on an ordinary message' do
    described_class.new(inbound('oi, tudo bem?')).perform

    expect(ChatflowExecution.where(chatflow: chatflow).count).to eq(0)
  end
end
