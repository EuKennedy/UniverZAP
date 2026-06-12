# Fires the Chatflow engine on every inbound customer message. The engine
# itself decides whether the message starts a new flow, advances a flow that
# is waiting on a menu reply, or is a no-op. Kept thin so the heavy lifting
# (and DB work) happens off the request path inside Chatflow::EngineJob.
class ChatflowListener < BaseListener
  def message_created(event)
    message, = extract_message_and_account(event)
    return unless eligible?(message)

    Chatflow::EngineJob.perform_later(message.id)
  end

  private

  def eligible?(message)
    return false if message.blank?
    return false unless message.incoming?
    return false if message.private?

    true
  end
end
