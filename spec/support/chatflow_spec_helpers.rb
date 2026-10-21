# Montagem de fluxos nos specs do Chatflow: etapas, ligações, a cliente
# escrevendo e o que o robô respondeu.
module ChatflowSpecHelpers
  def flow_node(chatflow, kind, config = {}, name = nil)
    ChatflowNode.create!(chatflow: chatflow, account: chatflow.account, kind: kind, name: name, config: config)
  end

  def flow_edge(source, target, handle = 'default')
    ChatflowEdge.create!(chatflow: source.chatflow, account: source.account, source_node_id: source.id,
                         target_node_id: target.id, source_handle: handle)
  end

  def customer_says(conversation, text)
    message = create(:message, conversation: conversation, account: conversation.account,
                               message_type: 'incoming', content: text)
    Chatflow::EngineService.new(message).perform
    message
  end

  def bot_said(conversation)
    conversation.messages.where(message_type: 'outgoing').order(:id).pluck(:content)
  end
end

RSpec.configure { |config| config.include ChatflowSpecHelpers }
