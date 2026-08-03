# Runs one lab duel in the background.
#
# A replay is a real Claude call, so a batch of twenty would hold an HTTP
# request open for a minute. It also must never compete with customer traffic
# for workers, hence the :low lane: a customer waiting on WhatsApp always wins
# over an experiment.
class Ai::AbReplayJob < ApplicationJob
  queue_as :low

  def perform(invocation_id, version_id)
    version = Ai::PromptVersion.find_by(id: version_id)
    invocation = Ai::Invocation.find_by(id: invocation_id)
    return if version.blank? || invocation.blank?
    return unless same_account?(invocation, version)

    Ai::AbReplayService.new(invocation: invocation, version: version).perform
  rescue Ai::AbReplayService::AlreadyCompared
    # Re-running a batch is a normal operator action; the unique index makes it
    # idempotent and this makes it quiet.
    nil
  rescue StandardError => e
    Rails.logger.error("[Athenas lab] replay failed invocation=#{invocation_id} version=#{version_id}: #{e.message}")
  end

  private

  # Defense in depth: a replay reads a customer question and writes an answer,
  # so a crossed id must never let one tenant's log feed another's experiment.
  def same_account?(invocation, version)
    return true if invocation.account_id == version.account_id

    Rails.logger.error(
      "[Athenas lab] cross-account replay blocked invocation=#{invocation.id} version=#{version.id}"
    )
    false
  end
end
