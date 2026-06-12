class Chatflow::EngineJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.nil?

    Chatflow::EngineService.new(message).perform
  end
end
