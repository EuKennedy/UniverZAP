# The commercial panel: what the agent cost, what it brought in, and the two
# numbers an operator actually repeats to someone else.
#
# Every figure here is measured. Cost comes from the credit ledger (what was
# really debited), revenue from the attribution ledger (what a human or an
# integration explicitly credited). Nothing is estimated except `hours_saved`,
# which is labelled as a model and carries its assumption in the payload.
class Ai::RoiService
  DEFAULT_DAYS = 30
  MAX_DAYS = 365
  # Average time a human takes to read and answer one WhatsApp message. The one
  # assumption in this file, returned alongside the result so nobody quotes the
  # number without it.
  SECONDS_PER_HUMAN_REPLY = 90

  def initialize(assistant:, days: DEFAULT_DAYS)
    @assistant = assistant
    @days = days.to_i.clamp(1, MAX_DAYS)
  end

  def perform
    {
      period_days: @days,
      cost_brl: cost_brl,
      revenue_brl: revenue_brl,
      roi: roi,
      replies: replies,
      conversations: conversations,
      cost_per_conversation_brl: per(cost_brl, conversations),
      cost_per_booking_brl: per(cost_brl, bookings),
      bookings: bookings,
      hours_saved: hours_saved,
      hours_saved_assumption_seconds: SECONDS_PER_HUMAN_REPLY,
      after_hours_revenue_brl: after_hours_revenue,
      by_source: by_source
    }
  end

  private

  # Customer-facing spend only. Lab replays are billed to the same balance but
  # they are an experiment, and charging the ROI of the service with the cost of
  # testing it would punish exactly the operator who tests before shipping.
  def invocations
    @invocations ||= @assistant.invocations.live
                               .where.not(phase: 'replay')
                               .where(created_at: @days.days.ago..)
  end

  def revenue_scope
    @revenue_scope ||= Ai::RevenueEvent.where(ai_assistant_id: @assistant.id)
                                       .where(occurred_at: @days.days.ago..)
  end

  # What was actually debited from the operator's balance, not a conversion of
  # the USD figure.
  def cost_brl
    @cost_brl ||= Ai::CreditLedgerEntry.where(ai_invocation_id: invocations.select(:id), kind: 'consumption')
                                       .sum(:amount_cents_brl).abs / 100.0
  end

  def revenue_brl
    @revenue_brl ||= revenue_scope.sum(:amount_brl).to_f
  end

  # Nil rather than zero when there is no cost yet: "0x return" reads as failure
  # when the truth is "not measurable yet".
  def roi
    return nil if cost_brl.zero?

    (revenue_brl / cost_brl).round(2)
  end

  def replies
    @replies ||= invocations.replies.distinct.count(:message_id)
  end

  def conversations
    @conversations ||= invocations.where.not(conversation_id: nil).distinct.count(:conversation_id)
  end

  def bookings
    @bookings ||= revenue_scope.where(source: 'agendamento').count
  end

  def hours_saved
    ((replies * SECONDS_PER_HUMAN_REPLY) / 3600.0).round(1)
  end

  # Summed in Ruby so the hour is read in the business's own timezone. The row
  # count here is sales, not calls, so loading them is cheap.
  def after_hours_revenue
    revenue_scope.select(&:after_hours?).sum { |event| event.amount_brl.to_f }.round(2)
  end

  def by_source
    revenue_scope.group(:source).sum(:amount_brl)
                 .transform_values { |value| value.to_f.round(2) }
  end

  def per(total, count)
    return nil if count.to_i.zero?

    (total / count).round(4)
  end
end
