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
    return unless credits_to_spare?(version.account)

    Ai::AbReplayService.new(invocation: invocation, version: version).perform
  rescue Ai::AbReplayService::AlreadyCompared
    # Re-running a batch is a normal operator action; the unique index makes it
    # idempotent and this makes it quiet.
    nil
  rescue StandardError => e
    Rails.logger.error("[Athenas lab] replay failed invocation=#{invocation_id} version=#{version_id}: #{e.message}")
  end

  private

  # The lab spends the SAME balance the agent answers customers with. A batch of
  # replays run on a low balance would buy an experiment with the credits a real
  # customer's reply needed, and the customer is the one who notices. Experiments
  # only run when there is room to spare.
  def credits_to_spare?(account)
    return true if Ai::CreditLedger.new(account).threshold_status == :ok

    Rails.logger.info("[Athenas lab] replay skipped, balance is not healthy account=#{account.id}")
    false
  rescue StandardError => e
    Rails.logger.warn("[Athenas lab] could not read balance account=#{account.id}: #{e.message}")
    false
  end

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
