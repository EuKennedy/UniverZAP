# Single entry point for ActionCable broadcasts on Task lifecycle.
# Mirrors the Kanban::Automations::Dispatcher shape — every callback
# pumps through here so the rescue/log policy lives in one place.
#
# Streams:
#   account-wide  → "account_<account_id>_tasks"
#   per-user      → "account_<account_id>_user_<user_id>_tasks"
#
# The per-user stream is used for "assigned to you" notifications so
# the dashboard can flash a toast specifically for the recipient
# without leaking the event to other agents on the same account.
class Tasks::Broadcaster
  ACCOUNT_STREAM_PREFIX = 'account_'.freeze
  USER_STREAM_INFIX = '_user_'.freeze
  STREAM_SUFFIX = '_tasks'.freeze

  def self.broadcast(event, task, target: :account, user: nil, payload: nil)
    return if task.blank? || task.account_id.blank?
    return if target == :user && user.blank?

    stream = stream_name(task, target, user)
    body = { event: event, data: payload || task.push_event_data }
    ActionCable.server.broadcast(stream, body)
  rescue StandardError => e
    # Broadcaster runs inside after_commit callbacks. A failure here
    # MUST NOT bubble — log and swallow so the user-visible Task
    # mutation still succeeds.
    Rails.logger.error(
      "[Tasks::Broadcaster] event=#{event} task=#{task&.id} target=#{target} failed: #{e.message}"
    )
  end

  def self.stream_name(task, target, user)
    base = "#{ACCOUNT_STREAM_PREFIX}#{task.account_id}"
    return "#{base}#{USER_STREAM_INFIX}#{user.id}#{STREAM_SUFFIX}" if target == :user

    "#{base}#{STREAM_SUFFIX}"
  end
end
