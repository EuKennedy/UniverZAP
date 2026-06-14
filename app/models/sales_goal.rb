# == Schema Information
#
# Table name: sales_goals
#
#  id            :bigint           not null, primary key
#  account_id    :bigint           not null
#  user_id       :bigint           not null
#  period        :integer          default(0), not null
#  target_amount :decimal(12, 2)   default(0.0), not null
#  active        :boolean          default(TRUE), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# A sales goal is a target amount an admin sets for an agent (atendente) over a
# recurring window (daily/weekly/monthly). Progress is derived live from the
# agent's sale_records within the current window — nothing is denormalised.
class SalesGoal < ApplicationRecord
  belongs_to :account
  belongs_to :user

  # daily   — window resets each day (beginning_of_day).
  # weekly  — window resets each week (beginning_of_week).
  # monthly — window resets each month (beginning_of_month).
  enum period: { daily: 0, weekly: 1, monthly: 2 }, _prefix: :period

  validates :target_amount, numericality: { greater_than_or_equal_to: 0 }

  # Start of the current goal window, used as the lower bound for summing sales.
  def period_start
    case period.to_sym
    when :daily then Time.current.beginning_of_day
    when :weekly then Time.current.beginning_of_week
    else Time.current.beginning_of_month
    end
  end

  # Total value the agent has registered within the current window.
  def current_amount
    account.sale_records
           .where(user_id: user_id)
           .where('recorded_at >= ?', period_start)
           .sum(:amount)
  end

  def progress
    current = current_amount
    {
      target: target_amount,
      current: current,
      remaining: [target_amount - current, 0].max,
      percent: target_amount.positive? ? [(current / target_amount * 100).round, 100].min : 0
    }
  end
end
