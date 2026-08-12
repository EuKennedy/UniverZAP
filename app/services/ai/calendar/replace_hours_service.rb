# Rewrites a professional's whole week in one go.
#
# Replace and not merge, because the screen edits the week as a single object:
# the operator deletes Saturday by leaving it empty, and a merge would keep
# Saturday open forever with nobody able to explain why.
class Ai::Calendar::ReplaceHoursService
  class Overlap < StandardError; end

  def initialize(professional:, ranges:)
    @professional = professional
    @ranges = Array(ranges)
  end

  def perform
    rows = @ranges.filter_map { |range| normalize(range) }
    reject_overlaps!(rows)

    Ai::Calendar::Hour.transaction do
      @professional.hours.delete_all
      rows.each { |row| @professional.hours.create!(row.merge(account_id: @professional.account_id)) }
    end
    @professional.hours.reload
  end

  private

  def normalize(range)
    weekday = range[:weekday].presence && range[:weekday].to_i
    starts_at = range[:starts_at].presence
    ends_at = range[:ends_at].presence
    return nil if weekday.nil? || starts_at.blank? || ends_at.blank?

    { weekday: weekday, starts_at: starts_at, ends_at: ends_at }
  end

  # Two overlapping ranges on the same day would offer the same slot twice, and
  # the customer would be shown 14:00 twice in one list. The model can only see
  # one row at a time, so the check has to live here.
  def reject_overlaps!(rows)
    rows.group_by { |row| row[:weekday] }.each_value do |day|
      ordered = day.sort_by { |row| minutes(row[:starts_at]) }
      ordered.each_cons(2) do |before, after|
        raise Overlap, "faixas sobrepostas no dia #{before[:weekday]}" if minutes(after[:starts_at]) < minutes(before[:ends_at])
      end
    end
  end

  # Accepts "09:00" from the screen and a Time from a form helper, because both
  # reach here and neither is wrong.
  def minutes(value)
    return (value.hour * 60) + value.min if value.respond_to?(:hour)

    hour, minute = value.to_s.split(':')
    (hour.to_i * 60) + minute.to_i
  end
end
