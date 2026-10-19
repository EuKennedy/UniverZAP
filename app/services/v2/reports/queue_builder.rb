# Queue and speed block of the management dashboard: how many open
# conversations never got a reply, how many have the contact waiting past the
# risk threshold, and how fast the first reply came in the period.
class V2::Reports::QueueBuilder
  include V2::Reports::DashboardScopes

  pattr_initialize [:account!, :params!]

  AT_RISK_SAMPLE = 10

  def build
    {
      open: open_scope.count,
      waiting: waiting_scope.count,
      at_risk: at_risk_scope.count,
      created: period_scope.count,
      replied: period_scope.where.not(first_reply_created_at: nil).count,
      median_first_response_seconds: median_first_response,
      at_risk_conversations: at_risk_conversations
    }
  end

  private

  def median_first_response
    period_scope.where.not(first_reply_created_at: nil).pick(MEDIAN_FIRST_RESPONSE)&.round
  end

  def at_risk_conversations
    at_risk_scope.includes(:contact, :assignee).order(:waiting_since).limit(AT_RISK_SAMPLE).map do |conversation|
      {
        id: conversation.display_id,
        contact: conversation.contact&.name,
        assignee: conversation.assignee&.name,
        waiting_since: conversation.waiting_since
      }
    end
  end
end
