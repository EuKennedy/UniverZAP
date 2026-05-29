# Real-time channel for team-chat events. Same pubsub_token + user_id
# handshake as AccountTasksChannel so we reuse the existing connection
# identifier scheme. One stream per account — every member of the account
# receives channel + message events.
#
# The subscription is rejected unless the user belongs to the account so
# a leaked pubsub_token can't snoop another tenant's chat.
class AccountTeamChatChannel < ApplicationCable::Channel
  def subscribed
    user = User.find_by(pubsub_token: params[:pubsub_token], id: params[:user_id])
    return reject if user.blank?

    account_id = params[:account_id].to_i
    return reject unless user.account_users.exists?(account_id: account_id)

    stream_from "account_#{account_id}_team_chat"
  end

  def unsubscribed
    stop_all_streams
  end
end
