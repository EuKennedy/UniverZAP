require 'rails_helper'

RSpec.describe Chatflow::EngineService do
  let(:flow) { create(:whatsapp_flow, :published) }
  let(:account) { flow.account }
  let(:inbox) { flow.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:chatflow) { Chatflow.create!(account: account, name: 'Agenda', inbox: inbox, status: :active) }

  let!(:send_flow) do
    ChatflowNode.create!(chatflow: chatflow, account: account, kind: :send_flow, name: 'Formulário',
                         config: { 'whatsapp_flow_id' => flow.id, 'text' => 'Toque para agendar', 'cta' => 'Agendar' })
  end
  let!(:thanks) { ChatflowNode.create!(chatflow: chatflow, account: account, kind: :send_message, config: { 'text' => 'Recebido!' }) }
  let!(:to_human) { ChatflowNode.create!(chatflow: chatflow, account: account, kind: :send_message, config: { 'text' => 'Já te atendo.' }) }

  def wire(handle, target)
    ChatflowEdge.create!(chatflow: chatflow, account: account, source_node_id: send_flow.id,
                         target_node_id: target.id, source_handle: handle)
  end

  def bot_said
    conversation.messages.where(message_type: 'outgoing').order(:id).pluck(:content)
  end

  def inbound(content, content_attributes = {})
    create(:message, conversation: conversation, account: account, message_type: 'incoming',
                     content: content, content_attributes: content_attributes)
  end

  describe 'enviar o formulário' do
    before { chatflow.update!(start_node: send_flow) }

    it 'manda o Flow e fica esperando' do
      described_class.force_start(chatflow, conversation)

      sent = conversation.messages.outgoing.last
      expect(sent.content_attributes['whatsapp_flow']['meta_flow_id']).to eq(flow.meta_flow_id)
      expect(sent.content_attributes['whatsapp_flow']['mode']).to eq('published')
      expect(ChatflowExecution.last).to be_status_waiting_input
    end

    # Em modo de teste, a Meta pede para mandar o rascunho — e é só assim que
    # o operador vê o formulário antes de publicar.
    it 'manda o rascunho quando o fluxo está em modo de teste' do
      flow.update!(status: 'draft')
      chatflow.update!(test_mode: true, test_phone: '5511999999999')

      described_class.force_start(chatflow, conversation)

      expect(conversation.messages.outgoing.last.content_attributes['whatsapp_flow']['mode']).to eq('draft')
    end

    it 'pula a etapa quando o Flow não é desta caixa' do
      other = create(:whatsapp_flow, :published, account: account)
      send_flow.update!(config: send_flow.config.merge('whatsapp_flow_id' => other.id))
      wire('default', thanks)

      described_class.force_start(chatflow, conversation)

      expect(bot_said).to eq(['Recebido!'])
    end
  end

  describe 'avançar' do
    let!(:execution) do
      ChatflowExecution.create!(account: account, chatflow: chatflow, conversation: conversation,
                                current_node: send_flow, status: :waiting_input)
    end

    before { wire('default', thanks) }

    it 'segue pela saída normal quando a resposta deste formulário chega' do
      message = inbound('Serviço: Corte', { flow_response: { flow_id: flow.id, fields: [] } })
      described_class.new(message).perform

      expect(bot_said).to eq(['Recebido!'])
      expect(execution.reload).to be_status_completed
    end

    it 'continua esperando quando o cliente digita e não há saída de fallback' do
      described_class.new(inbound('oi?')).perform

      expect(bot_said).to be_empty
      expect(execution.reload).to be_status_waiting_input
    end

    it 'sai pelo fallback quando ele está ligado e o cliente digita' do
      wire(ChatflowNode::FALLBACK, to_human)

      described_class.new(inbound('prefiro falar com alguém')).perform

      expect(bot_said).to eq(['Já te atendo.'])
    end

    it 'trata resposta de outro formulário como texto' do
      wire(ChatflowNode::FALLBACK, to_human)
      message = inbound('x', { flow_response: { flow_id: flow.id + 999, fields: [] } })

      described_class.new(message).perform

      expect(bot_said).to eq(['Já te atendo.'])
    end
  end
end
