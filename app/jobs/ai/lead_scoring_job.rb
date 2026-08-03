# Scores one closed conversation for the commercial radar.
#
# Runs in the background because it makes a (cheap) model call, and on the :low
# lane because a customer waiting on WhatsApp always outranks an analysis of a
# conversation that already ended.
class Ai::LeadScoringJob < ApplicationJob
  queue_as :low

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank? || conversation.sandbox?
    return if converted?(conversation)

    Ai::LeadTemperatureService.new(conversation: conversation).perform
  rescue StandardError => e
    Rails.logger.warn("[Athenas radar] scoring failed conv=#{conversation_id}: #{e.message}")
  end

  private

  # A conversation that already produced revenue is not an opportunity, it is a
  # result. Putting it in the radar would send a follow-up to someone who
  # already bought.
  def converted?(conversation)
    Ai::RevenueEvent.exists?(conversation_id: conversation.id)
  end
end
