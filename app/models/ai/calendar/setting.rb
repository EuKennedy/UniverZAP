# The rules that decide what the agent may offer. One row per assistant,
# created with defaults the first time a calendar is connected.
#
# Every one of these is here because its absence is felt in the first week of
# real use rather than in a demo.
class Ai::Calendar::Setting < ApplicationRecord
  self.table_name = 'ai_calendar_settings'

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account

  validates :minimum_lead_minutes, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10_080 }
  validates :horizon_days, numericality: { greater_than: 0, less_than_or_equal_to: 365 }
  validates :cancellation_window_hours, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 168 }

  # The window the agent may offer at all: never sooner than the operator can be
  # ready, never further out than they can plan for.
  def bookable_range(now = Time.current)
    (now + minimum_lead_minutes.minutes)..(now + horizon_days.days)
  end

  def push_event_data
    {
      minimum_lead_minutes: minimum_lead_minutes,
      horizon_days: horizon_days,
      cancellation_window_hours: cancellation_window_hours
    }
  end
end
