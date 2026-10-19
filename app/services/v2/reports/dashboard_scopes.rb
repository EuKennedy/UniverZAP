# Shared vocabulary of the management dashboard builders. Every number on the
# page comes from columns the conversation list already relies on:
#   - first_reply_created_at: first valid (human) reply;
#   - awaiting_reply + waiting_since: the contact has the last word since then.
# The period (since/until) always filters conversations.created_at; the queue
# (waiting, at risk) is live and ignores the period.
module V2::Reports::DashboardScopes
  DEFAULT_RISK_MINUTES = 30
  DEFAULT_PERIOD = 30.days

  MEDIAN_FIRST_RESPONSE = Arel.sql(
    'PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (conversations.first_reply_created_at - conversations.created_at)))'
  )
  REPLIED = Arel.sql('COUNT(conversations.first_reply_created_at)')
  RESOLVED = Arel.sql("COUNT(*) FILTER (WHERE conversations.status = #{Conversation.statuses[:resolved]})")

  private

  def conversations
    account.conversations.unscope(:order)
  end

  def period_scope
    conversations.where(created_at: range)
  end

  def open_scope
    conversations.where(status: :open)
  end

  def waiting_scope
    open_scope.where(first_reply_created_at: nil)
  end

  def at_risk_scope
    open_scope.where(awaiting_reply: true).where(conversations: { waiting_since: ..risk_minutes.minutes.ago })
  end

  def range
    since = params[:since].present? ? Time.zone.at(params[:since].to_i) : DEFAULT_PERIOD.ago
    # `until` arrives in whole seconds; cover that whole second.
    till = params[:until].present? ? Time.zone.at(params[:until].to_i + 1) : Time.current
    since...till
  end

  def risk_minutes
    params[:risk_minutes].presence&.to_i || DEFAULT_RISK_MINUTES
  end

  def conversion_label
    params[:conversion_label].presence
  end

  # { group_key => converted count }, or nil when no label was chosen: the
  # column then reads as "not measured" instead of a false zero.
  def converted_by(scope, group)
    return nil if conversion_label.nil?

    scope.tagged_with(conversion_label, on: :labels).group(group).count
  end
end
