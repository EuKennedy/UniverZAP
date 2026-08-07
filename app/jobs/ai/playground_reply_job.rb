# Generates one playground turn outside the web request.
#
# The turn takes 20-40s — a full Claude round trip plus however many tool-loop
# iterations the agent needs — and rack-timeout kills a web request at 15s. The
# operator saw an Internal Server Error and the reply was never produced, while
# the very same call succeeded from a console. Production never had the problem:
# real conversations already run through Ai::AutopilotReplyJob. This puts the
# playground on the same footing.
#
# The reply lands in the sandbox transcript, which the UI polls, so nothing here
# has to answer the browser.
class Ai::PlaygroundReplyJob < ApplicationJob
  queue_as :low

  def perform(assistant_id, user_id, text)
    assistant = Ai::Assistant.find_by(id: assistant_id)
    user = User.find_by(id: user_id)
    return if assistant.blank? || user.blank?

    Ai::PlaygroundService.new(account: assistant.account, assistant: assistant, user: user)
                         .send_message(text)
  rescue StandardError => e
    # PlaygroundService already writes ClaudeService errors into the transcript;
    # anything reaching here is unexpected and would otherwise vanish, leaving
    # the operator watching a spinner that never resolves.
    Rails.logger.error("[Athenas playground] turn failed assistant=#{assistant_id}: #{e.message}")
  end
end
