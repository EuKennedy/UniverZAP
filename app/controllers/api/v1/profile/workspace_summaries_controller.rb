# UniverZAP: per-account counters for the account switcher. Only data the
# user already owns (their unread, non-snoozed notifications, the same rule
# as the notification bell), counted in one grouped query.
class Api::V1::Profile::WorkspaceSummariesController < Api::BaseController
  def show
    counts = current_user.notifications
                         .where(account_id: current_user.account_ids, read_at: nil, snoozed_until: nil)
                         .group(:account_id)
                         .count
    render json: {
      payload: current_user.account_ids.map { |id| { account_id: id, unread_notifications_count: counts.fetch(id, 0) } }
    }
  end
end
