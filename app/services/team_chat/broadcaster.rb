# Single entry point for ActionCable broadcasts on team-chat events.
# Mirrors Tasks::Broadcaster — one account-wide stream, all members of
# the account subscribe to it. No per-user stream: every agent sees every
# channel by design (internal tool), so targeted delivery would be noise.
#
# Stream: "account_<account_id>_team_chat"
class TeamChat::Broadcaster
  STREAM_PREFIX = 'account_'.freeze
  STREAM_SUFFIX = '_team_chat'.freeze

  def self.broadcast(event, account_id, payload)
    return if account_id.blank?

    ActionCable.server.broadcast(stream_name(account_id), { event: event, data: payload })
  rescue StandardError => e
    # Runs inside after_commit callbacks — a broadcast failure MUST NOT
    # bubble and roll back the user-visible message/channel mutation.
    Rails.logger.error("[TeamChat::Broadcaster] event=#{event} account=#{account_id} failed: #{e.message}")
  end

  def self.stream_name(account_id)
    "#{STREAM_PREFIX}#{account_id}#{STREAM_SUFFIX}"
  end
end
