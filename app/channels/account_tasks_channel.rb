# Real-time channel for Task events. Mirrors the RoomChannel handshake
# (pubsub_token + user_id) so we don't need a parallel connection
# identifier scheme. Two streams per user:
#   - `account_<id>_tasks` — every Task event for the account
#   - `account_<id>_user_<uid>_tasks` — events targeted at this user
#                                       (e.g. `task.assigned_to_you`)
#
# The subscription is rejected unless the user actually belongs to the
# account so a leaked pubsub_token can't snoop another tenant's stream.
class AccountTasksChannel < ApplicationCable::Channel
  def subscribed
    user = User.find_by(pubsub_token: params[:pubsub_token], id: params[:user_id])
    return reject if user.blank?

    account_id = params[:account_id].to_i
    return reject unless user.account_users.exists?(account_id: account_id)

    stream_from "account_#{account_id}_tasks"
    stream_from "account_#{account_id}_user_#{user.id}_tasks"
  end

  def unsubscribed
    stop_all_streams
  end
end
