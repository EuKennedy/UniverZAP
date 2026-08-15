# What the agents brought in: leads left on the table, sales credited to them,
# and appointments they put on the agenda.
#
# Cost is easy to measure and worthless on its own. These are the numbers that
# turn "the agent spent R$ 40" into a decision, and every one of them is
# recorded rather than modelled: a lead is a conversation that ended without a
# sale, a revenue event is money a human or an integration explicitly credited,
# and an appointment is a row we wrote when we booked it.
class Ai::Reports::CommercialMetrics
  def initialize(account:, days:, zone:)
    @account = account
    @days = days
    @zone = zone
  end

  # Memoized, like every public reader here: the orchestrator reads revenue and
  # bookings both for the summary and to divide by, and by_agent once per row of
  # the comparison table. Unmemoized, a fixed set of queries becomes one per
  # agent.
  def leads
    @leads ||= build_leads
  end

  def revenue
    @revenue ||= build_revenue
  end

  def bookings
    @bookings ||= build_bookings
  end

  def by_agent
    @by_agent ||= build_by_agent
  end

  private

  def build_leads
    counts = leads_scope.group(:status).count
    {
      total: counts.values.sum,
      by_status: Ai::LeadOpportunity::STATUSES.index_with { |status| counts[status].to_i },
      by_band: bands,
      by_block_reason: leads_scope.where.not(block_reason: nil).group(:block_reason).count,
      potential_brl: leads_scope.open_leads.sum(:potential_brl).to_f.round(2),
      won_brl: leads_scope.where(status: 'won').sum(:won_brl).to_f.round(2)
    }
  end

  def build_revenue
    {
      total_brl: revenue_scope.sum(:amount_brl).to_f.round(2),
      by_source: revenue_scope.group(:source).sum(:amount_brl).transform_values { |v| v.to_f.round(2) },
      after_hours_brl: after_hours_revenue,
      events: revenue_scope.count
    }
  end

  # Only the agenda we host. A salon booking through belezaki writes to the
  # salon's own system and leaves no row here, so counting zero for that agent
  # would read as "the agent booked nothing" when it means "we do not hold the
  # book". The provider travels with the number so the screen can say so.
  def build_bookings
    { booked: appointments_scope.booked.count, cancelled: appointments_scope.where(status: 'cancelled').count }
  end

  def build_by_agent
    ids = @account.ai_assistants.pluck(:id)
    ids.index_with do |id|
      {
        leads_open: leads_by_agent.dig(id, 'open').to_i,
        leads_hot: hot_leads_by_agent[id].to_i,
        revenue_brl: revenue_by_agent[id].to_f.round(2),
        bookings: bookings_by_agent[id].to_i
      }
    end
  end

  # `last_seen_at`, not `created_at`: a lead is a live thing that warms and
  # cools, and the question the panel answers is which ones moved in the period.
  def leads_scope
    @leads_scope ||= Ai::LeadOpportunity.where(account_id: @account.id, last_seen_at: @days.days.ago..)
  end

  def revenue_scope
    @revenue_scope ||= Ai::RevenueEvent.where(account_id: @account.id, occurred_at: @days.days.ago..)
  end

  def appointments_scope
    @appointments_scope ||= Ai::Calendar::Appointment.where(account_id: @account.id, created_at: @days.days.ago..)
  end

  def bands
    {
      'hot' => leads_scope.hot.count,
      'warm' => leads_scope.warm.count,
      'cold' => leads_scope.cold.count
    }
  end

  # Summed in Ruby so the hour is read on the business's clock. These are sales,
  # not Claude calls, so the row count stays small enough to load.
  def after_hours_revenue
    revenue_scope.select { |event| event.after_hours?(@zone) }
                 .sum { |event| event.amount_brl.to_f }.round(2)
  end

  def leads_by_agent
    @leads_by_agent ||= build_leads_by_agent
  end

  def build_leads_by_agent
    counted = leads_scope.group(:ai_assistant_id, :status).count
    counted.each_with_object({}) do |((id, status), count), out|
      (out[id] ||= {})[status] = count
    end
  end

  def hot_leads_by_agent
    @hot_leads_by_agent ||= leads_scope.open_leads.hot.group(:ai_assistant_id).count
  end

  def revenue_by_agent
    @revenue_by_agent ||= revenue_scope.group(:ai_assistant_id).sum(:amount_brl)
  end

  def bookings_by_agent
    @bookings_by_agent ||= appointments_scope.booked.group(:ai_assistant_id).count
  end
end
