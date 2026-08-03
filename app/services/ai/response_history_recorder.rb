# Projects one delivered reply into ai_response_histories — the capped store the
# Histórico tab reads — and trims the agent's window back down to the cap.
#
# Called right AFTER a turn's reply is committed (Ai::AutopilotReplyJob), so it
# runs outside the conversation lock: it can neither extend that transaction nor
# cost the reply if it fails. A missing history row is a line absent from one
# screen, never a message the customer didn't get.
#
# A turn can bill several Claude calls (a tool loop), so the telemetry is summed
# over the turn and the review fields are read from its last call — the shaping
# the analytics screen used to do live on every request, moved here so the read
# stays "last N rows" instead of a per-request aggregation over the whole log.
class Ai::ResponseHistoryRecorder
  def initialize(assistant:, conversation:, message:)
    @assistant = assistant
    @conversation = conversation
    @message = message
  end

  def self.record!(assistant:, conversation:, message:)
    new(assistant: assistant, conversation: conversation, message: message).record!
  rescue StandardError => e
    Rails.logger.warn("[Athenas history] projection failed message=#{message&.id}: #{e.message}")
  end

  def record!
    invocations = turn_invocations
    return if invocations.empty?

    # create_or_find_by absorbs the retried turn that re-delivers the same
    # message: the unique (ai_assistant_id, message_id) index makes the second
    # attempt a no-op instead of a duplicate row.
    Ai::ResponseHistory.create_or_find_by(ai_assistant: @assistant, message_id: @message.id) do |row|
      row.assign_attributes(row_attributes(invocations))
    end
    Ai::ResponseHistory.trim!(@assistant.id)
  end

  private

  # Exactly the calls that produced this reply, stamped with its message id by
  # the delivery step. No time window, so a neighbouring turn can't bleed in.
  def turn_invocations
    @assistant.invocations
              .where(conversation_id: @conversation.id, message_id: @message.id)
              .order(:created_at).to_a
  end

  def row_attributes(invocations)
    last = invocations.last
    {
      account: @assistant.account, conversation_id: @conversation.id,
      user_message: last.user_message,
      # The live message is the source of truth for what was delivered; the
      # logged snapshot is the fallback when it is blank.
      ai_response: @message.content.presence || last.ai_response,
      model: last.model, auto_flag: last.auto_flag, confidence: last.confidence,
      cost_brl: invocations.sum(&:cost_brl), cost_usd: invocations.sum(&:cost_usd),
      duration_ms: invocations.sum(&:duration_ms), calls: invocations.length
    }
  end
end
