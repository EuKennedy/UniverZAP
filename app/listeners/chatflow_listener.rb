# Fires the Chatflow engine on every inbound customer message. The engine
# itself decides whether the message starts a new flow, advances a flow that
# is waiting on a menu reply, or is a no-op. Kept thin so the heavy lifting
# (and DB work) happens off the request path inside Chatflow::EngineJob.
#
# Também: pausa o robô quando um atendente responde no meio de um fluxo
# (pelo painel ou pelo celular, que chega como a nota "📱 Enviado do
# WhatsApp"), dispara o gatilho "etiqueta adicionada" e limpa a pausa quando
# a conversa é resolvida.
class ChatflowListener < BaseListener
  def message_created(event)
    return if sandbox_event?(event)

    message, = extract_message_and_account(event)
    return if message.blank?

    if eligible?(message)
      Chatflow::EngineJob.perform_later(message.id)
    elsif human_reply?(message)
      Chatflow::BotControl.agent_replied(message.conversation, message.sender.is_a?(User) ? message.sender : nil)
    end
  end

  def conversation_updated(event)
    return if sandbox_event?(event)

    conversation = event.data[:conversation]
    previous, current = event.data[:changed_attributes].to_h.with_indifferent_access[:label_list]
    added = Array(current) - Array(previous)
    Chatflow::TriggerDispatcher.label_added(conversation, added) if added.any?
  end

  def conversation_resolved(event)
    return if sandbox_event?(event)

    Chatflow::BotControl.new(event.data[:conversation]).clear!
  end

  private

  def eligible?(message)
    return false unless message.incoming?
    return false if message.private?

    true
  end

  def human_reply?(message)
    return message.phone_reply_note? if message.private?

    message.outgoing? && message.sender_type == 'User'
  end
end
