class Whatsapp::Flows::ApplyResponseJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank?

    Whatsapp::Flows::ApplyResponseService.new(message).perform
  end
end
