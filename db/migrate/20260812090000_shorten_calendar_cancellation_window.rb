# Two hours, not four.
#
# The operator's call: past this point the agent stops touching an appointment
# and hands the conversation to a human instead. Four hours was my guess; two
# is what the business actually wants, and the difference is real money for the
# professional whose chair sits empty.
#
# A separate migration rather than an edit to the one that created the table:
# that one may already have run somewhere, and a changed default in an
# already-applied migration is a divergence nobody notices until two
# environments disagree.
class ShortenCalendarCancellationWindow < ActiveRecord::Migration[7.1]
  def up
    change_column_default :ai_calendar_settings, :cancellation_window_hours, from: 4, to: 2
  end

  def down
    change_column_default :ai_calendar_settings, :cancellation_window_hours, from: 2, to: 4
  end
end
