class Ai::PruneInvocationLogsJob < ApplicationJob
  queue_as :purgable

  # The system prompt snapshot (up to 80k chars) is the one column that makes
  # ai_invocations grow with traffic, and it is write-only: the A/B replay
  # rebuilds the prompt from the candidate version (see Ai::AbReplayService), and
  # nothing reads the logged copy. Past the retention window it is dead weight,
  # so we clear it while keeping everything the ROI, analytics and supervision
  # screens still read — cost, tokens, latency, flags, the short question/answer
  # text. Same column Conversation#scrub_ai_response_log clears on deletion, on a
  # schedule instead of on an event.
  RETENTION = 30.days
  # Cleared in batches so the first run over an existing backlog never takes one
  # long lock on the hottest table on the platform.
  BATCH_SIZE = 5_000

  def perform
    Ai::Invocation.where('created_at < ?', RETENTION.ago)
                  .where.not(system_prompt: nil)
                  .in_batches(of: BATCH_SIZE) do |batch|
      # rubocop:disable Rails/SkipsModelValidations
      batch.update_all(system_prompt: nil)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end
end
