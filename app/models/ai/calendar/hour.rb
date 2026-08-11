# One opening RANGE, not one row per day: a salon stops for lunch, and a single
# opens/closes pair per weekday would have the agent offering 12:30.
class Ai::Calendar::Hour < ApplicationRecord
  self.table_name = 'ai_calendar_hours'

  # 0 = Sunday, matching Ruby's Date#wday so nothing has to translate.
  WEEKDAYS = (0..6).to_a.freeze

  belongs_to :professional, class_name: 'Ai::Calendar::Professional',
                            foreign_key: :ai_calendar_professional_id, inverse_of: :hours
  belongs_to :account

  validates :weekday, inclusion: { in: WEEKDAYS }
  validates :starts_at, :ends_at, presence: true
  validate :ends_after_it_starts

  private

  # A range that ends before it begins produces no slots and no error, which is
  # the kind of configuration mistake that looks like "the agent is broken".
  def ends_after_it_starts
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, 'precisa ser depois do horário de início')
  end
end
