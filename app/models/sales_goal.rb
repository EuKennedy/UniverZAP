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

  # currency — progress rendered as BRL, fed by the in-chat "registrar venda".
  # count    — progress rendered as a plain number (e.g. "Depoimentos"), fed by
  #            the per-card register action on the Metas panel.
  enum unit: { currency: 0, count: 1 }, _prefix: :unit

  before_validation :assign_category

  validates :name, presence: true
  validates :target_amount, numericality: { greater_than_or_equal_to: 0 }

  # Start of the current goal window, used as the lower bound for summing sales.
  def period_start
    case period.to_sym
    when :daily then Time.current.beginning_of_day
    when :weekly then Time.current.beginning_of_week
    else Time.current.beginning_of_month
    end
  end

  # Total value the agent has registered within the current window, scoped to
  # this goal's category so a "Depoimentos" goal never counts sales and vice
  # versa.
  def current_amount
    account.sale_records
           .where(user_id: user_id, category: category)
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

  private

  # Currency goals always land on the shared 'sales' bucket so the in-chat sale
  # registration feeds them. Count goals get a slug derived from their name.
  def assign_category
    self.category = unit_currency? ? 'sales' : (name.to_s.parameterize.presence || 'meta')
  end
end
