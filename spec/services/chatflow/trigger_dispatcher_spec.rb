require 'rails_helper'

RSpec.describe Chatflow::TriggerDispatcher do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:abandoned) { create(:label, account: account, title: 'carrinho-abandonado') }

  def flow_with(trigger_type, config)
    flow = Chatflow.create!(account: account, name: trigger_type.to_s, status: :active, trigger_type: trigger_type, trigger_config: config)
    flow.update!(start_node: flow_node(flow, :send_message, 'text' => "fluxo #{trigger_type}"))
    flow
  end

  describe 'etiqueta adicionada' do
    let!(:flow) { flow_with(:label_added, 'label_ids' => [abandoned.id]) }

    it 'começa quando a etiqueta entra (pelo listener do conversation.updated)' do
      conversation.update_labels(['carrinho-abandonado'])
      event = Events::Base.new('conversation.updated', Time.zone.now,
                               conversation: conversation, changed_attributes: { 'label_list' => [[], ['carrinho-abandonado']] })
      ChatflowListener.instance.conversation_updated(event)

      expect(bot_said(conversation)).to eq(['fluxo label_added'])
      expect(ChatflowExecution.last.context['trigger']).to eq('label_added')
    end

    it 'ignora outras etiquetas e fluxo em rascunho' do
      described_class.label_added(conversation, ['vip'])
      flow.update!(status: :draft)
      described_class.label_added(conversation, ['carrinho-abandonado'])

      expect(bot_said(conversation)).to be_empty
    end

    it 'não atropela um fluxo vivo nem uma conversa pausada' do
      Chatflow::BotControl.new(conversation).pause!
      described_class.label_added(conversation, ['carrinho-abandonado'])

      expect(bot_said(conversation)).to be_empty
    end
  end

  describe 'entrou na lista' do
    let(:list) { Struct.new(:id).new(9) }

    it 'começa na conversa mais recente do contato' do
      flow_with(:list_entered, 'list_ids' => [9])
      older = create(:conversation, account: account, inbox: inbox, contact: conversation.contact, last_activity_at: 2.days.ago)
      conversation.update!(last_activity_at: 1.minute.ago)

      described_class.list_entered(list, conversation.contact)

      expect(bot_said(conversation)).to eq(['fluxo list_entered'])
      expect(bot_said(older)).to be_empty
    end

    it 'filtra pela lista escolhida' do
      flow_with(:list_entered, 'list_ids' => [3])
      described_class.list_entered(list, conversation.contact)

      expect(bot_said(conversation)).to be_empty
    end
  end

  describe 'respondeu a um disparo' do
    let(:broadcast) { create(:broadcast, account: account) }

    it 'começa na primeira resposta e não nas seguintes' do
      flow_with(:broadcast_reply, 'broadcast_ids' => [broadcast.id])
      create(:broadcast_recipient, broadcast: broadcast, contact: conversation.contact, status: :delivered, sent_at: 1.hour.ago)

      customer_says(conversation, 'quero sim!')
      expect(bot_said(conversation)).to eq(['fluxo broadcast_reply'])

      BroadcastRecipient.update_all(replied_at: 10.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      ChatflowExecution.update_all(status: ChatflowExecution.statuses[:completed]) # rubocop:disable Rails/SkipsModelValidations
      customer_says(conversation, 'oi de novo')
      expect(bot_said(conversation).size).to eq(1)
    end

    it 'não começa sem disparo recente' do
      flow_with(:broadcast_reply, {})
      create(:broadcast_recipient, broadcast: broadcast, contact: conversation.contact, status: :delivered, sent_at: 10.days.ago)

      customer_says(conversation, 'oi')
      expect(bot_said(conversation)).to be_empty
    end
  end
end
